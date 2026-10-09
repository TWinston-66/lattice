{
  config,
  lib,
  pkgs,
  ...
}:
# Books, with the Kindle as the only place they are read. The library is Audiobookshelf
# on labpi8, which abs-opds serves to KOReader on the (jailbroken) Kindle as an OPDS
# catalogue; KoInsight on the same box keeps the reading statistics and is KOReader's
# progress-sync server. Nothing here is a reader. What lattice adds:
#
#   - `lattice books add` puts an EPUB or PDF into Audiobookshelf, which is all it takes
#     for the Kindle to see it. An EPUB landing in ~/Downloads gets a banner offering the
#     same.
#   - Plugging the Kindle in (udiskie mounts it at /run/media/winston/Kindle) runs a sync:
#     KOReader's highlights become notes in the Obsidian vault, its statistics database
#     goes to KoInsight, and it ejects -- after offering to clear out crash dumps and the
#     macOS leftovers a Finder session sprays over a FAT disk.
#   - A bar pill reads KoInsight: the reading streak, and the book in progress.
let
  # SIGRTMIN+12, the signal the bar pill below listens for (waybar.nix checks that no two pills share one).
  barSignal = 12;

  cfg = config.lattice.books;

  home = config.users.users.winston.home;
  mount = "/run/media/winston/Kindle";

  # KOReader keeps a book's settings, highlights included, in metadata.<ext>.lua: a Lua
  # table literal behind `return`. Loading it as text-only code in an empty environment is
  # the reader KOReader itself uses, minus the globals -- a sidecar can't reach io or os,
  # and the caller wraps this in a timeout. One JSON line per sidecar, highlights only:
  # page bookmarks have no pos0 and no text.
  sidecars = pkgs.writeText "lattice-books-sidecars.lua" ''
    local function enc(v)
      local t = type(v)
      if t == "string" then
        local s = v:gsub('[%c"\\]', function(c)
          local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r' }
          return m[c] or string.format("\\u%04x", c:byte())
        end)
        return '"' .. s .. '"'
      elseif t == "number" then
        return string.format("%.14g", v)
      elseif t == "boolean" then
        return tostring(v)
      elseif t == "table" then
        local out = {}
        if v[1] ~= nil or next(v) == nil then
          for i = 1, #v do out[i] = enc(v[i]) end
          return "[" .. table.concat(out, ",") .. "]"
        end
        for k, x in pairs(v) do out[#out + 1] = enc(tostring(k)) .. ":" .. enc(x) end
        return "{" .. table.concat(out, ",") .. "}"
      end
      return "null"
    end

    for _, path in ipairs(arg) do
      local f = io.open(path, "rb")
      local src = f and f:read("a")
      if f then f:close() end
      local chunk = src and load(src, "=" .. path, "t", {})
      local ok, doc = false, nil
      if chunk then ok, doc = pcall(chunk) end
      if ok and type(doc) == "table" then
        local props, stats = doc.doc_props or {}, doc.stats or {}
        local marks = {}
        for _, a in ipairs(doc.annotations or {}) do
          if a.pos0 and type(a.text) == "string" and a.text ~= "" then
            marks[#marks + 1] = {
              text = a.text,
              note = a.note,
              chapter = a.chapter,
              page = a.pageno or (type(a.page) == "number" and a.page or nil),
              datetime = a.datetime,
            }
          end
        end
        print(enc({
          path = path,
          title = props.title or stats.title,
          authors = props.authors or stats.authors,
          percent = doc.percent_finished,
          highlights = marks,
        }))
      end
    end
  '';

  books = pkgs.writeShellApplication {
    name = "lattice-books";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.diffutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.libnotify
      pkgs.lua5_4
      pkgs.poppler-utils
      pkgs.procps
      pkgs.sqlite
      pkgs.systemd
      pkgs.udisks
      pkgs.unzip
      pkgs.util-linux
      pkgs.xmlstarlet
      config.programs.uwsm.package
    ];
    text = ''
      abs=${lib.escapeShellArg cfg.audiobookshelf}
      koinsight=${lib.escapeShellArg cfg.koinsight}
      token_file=${lib.escapeShellArg cfg.tokenFile}
      library_name=${lib.escapeShellArg cfg.library}
      kindle=${lib.escapeShellArg mount}
      vault=${lib.escapeShellArg cfg.highlightsDir}
      state=''${XDG_STATE_HOME:-$HOME/.local/state}/lattice/books

      signal() { pkill -RTMIN+${toString barSignal} -x waybar || true; }

      # Every banner from here replaces the last one, so a sync reads as one banner that
      # changes rather than a stack.
      notify() {
        notify-send -a Books -i accessories-ebook-reader \
          -h string:x-canonical-private-synchronous:lattice-books "$@" || true
      }

      die() { echo "lattice-books: $*" >&2; exit 1; }

      api() {
        [[ -r $token_file ]] || die "no Audiobookshelf token at $token_file (sops: abs-token)"
        local path=$1
        shift
        curl -fsS --max-time 60 -H "Authorization: Bearer $(<"$token_file")" "$@" "$abs/api$path"
      }

      # The library's id and its one folder's id, into the globals lib and folder.
      library() {
        IFS=$'\t' read -r lib folder < <(api /libraries | jq -r --arg n "$library_name" '
          .libraries[] | select(.name == $n) | [.id, .folders[0].id] | @tsv') \
          || die "no library named '$library_name' in Audiobookshelf"
      }

      # Title and author of an EPUB (its OPF), a PDF (its info dictionary), or failing
      # those the "Author - Title.ext" name most downloads arrive with. Into the globals
      # title and author.
      describe() {
        local f=$1 base opf
        base=$(basename "$f")
        base=''${base%.*}
        title="" author=""
        case ''${f,,} in
        *.epub)
          opf=$(unzip -p "$f" META-INF/container.xml 2>/dev/null \
            | xmlstarlet sel -N c=urn:oasis:names:tc:opendocument:xmlns:container \
                -t -v '//c:rootfile[1]/@full-path' 2>/dev/null || true)
          if [[ -n $opf ]]; then
            title=$(unzip -p "$f" "$opf" | xmlstarlet sel -N dc=http://purl.org/dc/elements/1.1/ \
              -t -v '(//dc:title)[1]' 2>/dev/null || true)
            author=$(unzip -p "$f" "$opf" | xmlstarlet sel -N dc=http://purl.org/dc/elements/1.1/ \
              -t -v '(//dc:creator)[1]' 2>/dev/null || true)
          fi
          ;;
        *.pdf)
          title=$(pdfinfo "$f" 2>/dev/null | sed -n 's/^Title: *//p' || true)
          author=$(pdfinfo "$f" 2>/dev/null | sed -n 's/^Author: *//p' || true)
          ;;
        esac
        if [[ -z $title && $base == *' - '* ]]; then
          author=''${author:-''${base%% - *}}
          title=''${base#* - }
        fi
        title=''${title:-$base}
        # A single newline-free line each: some OPFs wrap their titles.
        title=$(tr -s '\n\t ' '   ' <<<"$title" | sed 's/^ //; s/ $//')
        author=$(tr -s '\n\t ' '   ' <<<"$author" | sed 's/^ //; s/ $//')
      }

      # A curl -F value in double quotes, which is the only way it takes , and ; literally.
      quote() {
        local s=''${1//\\/\\\\}
        printf '"%s"' "''${s//\"/\\\"}"
      }

      add() {
        local force=0 f
        local -a files=()
        for f in "$@"; do
          if [[ $f == --force ]]; then force=1; else files+=("$f"); fi
        done
        ((''${#files[@]})) || die "usage: lattice books add [--force] <file>..."
        library
        local n=0
        for f in "''${files[@]}"; do
          [[ -f $f ]] || die "$f: no such file"
          case ''${f,,} in *.epub | *.pdf) ;; *) die "$f: only EPUB and PDF go in the library" ;; esac
          describe "$f"
          # The library's own search, so a book already there isn't uploaded twice under a
          # second folder.
          if ((!force)) && api "/libraries/$lib/search" -G --data-urlencode "q=$title" \
            | jq -e --arg t "$title" '
                def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
                any(.book[]?.libraryItem.media.metadata.title; norm == ($t | norm))' >/dev/null; then
            echo "$title is already in the library; --force adds it anyway" >&2
            notify "Already in the library" "$title"
            continue
          fi
          # Audiobookshelf files it under <folder>/<author>/<title>/ and its watcher picks
          # it up; the scan after is for the day the watcher is off.
          # The file goes up quoted -- unquoted, curl reads a comma in the path as a second
          # file -- and named for what it is rather than wherever it was downloaded from.
          api /upload -X POST -o /dev/null \
            -F "title=$title" -F "author=$author" -F "library=$lib" -F "folder=$folder" \
            -F "0=@$(quote "$f");filename=$(quote "$(safe "''${author:+$author - }$title").''${f##*.}")" \
            || die "upload of $f failed"
          echo "added: $title''${author:+ — $author}"
          n=$((n + 1))
        done
        ((n)) || return 0
        api "/libraries/$lib/scan" -X POST -o /dev/null || true
        # abs-opds keeps the library listing for an hour, hard-coded; restarting it is the
        # only way to empty that. Over SSH through Bitwarden's agent, so a locked vault only
        # means waiting out the hour.
        local when="Now in OPDS → homelab on the Kindle"
        if ! ${cfg.refreshCatalog} >/dev/null 2>&1; then when="In OPDS → homelab on the Kindle within the hour"; fi
        echo "$when"
        notify "Added to the library" "$title''${author:+ · $author}''${n:+$( ((n > 1)) && echo " and $((n - 1)) more")}"$'\n'"$when"
      }

      # Run by lattice-books-downloads.path on any change in ~/Downloads: an EPUB that has
      # arrived since the last look gets a banner. With no stamp yet, the last look is a
      # minute ago -- enough for the download that set this off, and not every book ever
      # downloaded.
      #
      # By ctime, not mtime: Firefox writes to a .part and renames it, and a rename keeps an
      # mtime that can be older than the last look. And the look is stamped when it starts,
      # not when it ends, then repeated until nothing is newer: a rename that lands while
      # this runs doesn't start it again (the unit is already active), so this run has to
      # be the one that sees it.
      downloads() {
        local stamp=$state/downloads-seen next=$state/downloads-seen.next f
        mkdir -p "$state"
        [[ -e $stamp ]] || touch -d '-1 minute' "$stamp"
        while :; do
          touch "$next"
          local -a new=()
          while IFS= read -r -d "" f; do new+=("$f"); done < <(find "$HOME/Downloads" -maxdepth 1 \
            -type f -iname '*.epub' -cnewer "$stamp" ! -cnewer "$next" -print0)
          mv -f "$next" "$stamp"
          for f in "''${new[@]}"; do setsid -f "$0" offer "$f" >/dev/null 2>&1 </dev/null; done
          [[ -n $(find "$HOME/Downloads" -maxdepth 1 -type f -iname '*.epub' -cnewer "$stamp" -print -quit) ]] \
            || break
        done
      }

      # mako draws no buttons, only the default action on a left click, so the body says
      # where to click; it expires after two minutes and nothing happens.
      offer() {
        local f=$1 action
        describe "$f"
        action=$(notify-send -a Books -i accessories-ebook-reader -t 120000 \
          -A default=Add "Add to the library?" \
          "$title''${author:+ · $author}"$'\n'"Click to send it to Audiobookshelf and the Kindle." || true)
        [[ $action == default ]] && add "$f"
      }

      # --- The Kindle -------------------------------------------------------------------

      # Files and folders that are safe to lose: KOReader and the Kindle's own crash dumps,
      # and what macOS leaves on any FAT disk it touches -- AppleDouble ._ files (checked by
      # their magic, not just the name), Spotlight's index and fseventsd's log. .Trashes is
      # left alone: it holds books deleted from a Mac, sidecars and all.
      junk() {
        find "$kindle" -maxdepth 1 \( -name '*.core' -o -name 'Indexer_Dump_*.txt' \
          -o -name .Spotlight-V100 -o -name .fseventsd \) -print0
        find "$kindle/documents" -maxdepth 1 -name '*_crash_*' -print0 2>/dev/null || true
        local f
        while IFS= read -r -d "" f; do
          if [[ $(od -An -tx1 -N4 "$f" | tr -d ' \n') == 00051607 ]]; then printf '%s\0' "$f"; fi
        done < <(find "$kindle" -path "$kindle/.Trashes" -prune -o -type f -name '._*' -print0)
      }

      clean() {
        mountpoint -q "$kindle" || die "the Kindle isn't mounted"
        local -a list=()
        local f
        while IFS= read -r -d "" f; do list+=("$f"); done < <(junk)
        ((''${#list[@]})) || { echo "nothing to clean"; return; }
        rm -rf -- "''${list[@]}"
        sync -f "$kindle"
        echo "removed ''${#list[@]} items"
      }

      eject() {
        local dev
        dev=$(findmnt -no SOURCE "$kindle") || return 0
        sync -f "$kindle"
        udisksctl unmount --no-user-interaction -b "$dev" >/dev/null
        udisksctl power-off --no-user-interaction -b "$dev" >/dev/null 2>&1 || true
      }

      # Highlights across every note, from their frontmatter.
      counted() {
        find "$vault" -maxdepth 1 -name '*.md' ! -name 00_Highlights.md \
          -exec awk '/^highlights: /{s+=$2} END{print s+0}' {} + 2>/dev/null \
          | awk '{s+=$1} END{print s+0}'
      }

      safe() { tr -d '\\/:*?"<>|#^[]' <<<"$1" | sed 's/^[ .]*//; s/[ .]*$//' | cut -c 1-120; }

      # Highlights into the vault, one note per book, rewritten whenever KOReader's copy
      # changes and left alone otherwise -- so the vault pill only counts real changes, and
      # a book deleted from the Kindle keeps its note. Prints how many highlights are new.
      highlights() {
        local -a metas=()
        local f
        while IFS= read -r -d "" f; do metas+=("$f"); done \
          < <(find "$kindle" -path "$kindle/system" -prune -o -type f -name 'metadata.*.lua' ! -name '._*' -print0)
        ((''${#metas[@]})) || { echo 0; return; }
        mkdir -p "$vault"

        local before after json title authors name tmp n
        before=$(counted)
        tmp=$(mktemp -d)
        # The same book can be both on the Kindle and in .Trashes; the copy with the most
        # highlights wins.
        timeout 30 lua ${sidecars} "''${metas[@]}" \
          | jq -sc 'map(select((.highlights | length) > 0 and .title != null))
                    | group_by([.title, .authors]) | map(max_by(.highlights | length))[]' \
          >"$tmp/books.jsonl" || true

        while IFS= read -r json; do
          title=$(jq -r .title <<<"$json")
          authors=$(jq -r '.authors // "" | gsub("\n"; ", ")' <<<"$json")
          name=$(safe "''${authors:+$authors - }$title")
          jq -r --arg authors "$authors" '
            def md: gsub("\n"; "\n> ");
            "---",
            "type: highlights",
            "area: \"[[00_Hobbies]]\"",
            "title: \(.title | tojson)",
            "author: \($authors | tojson)",
            "highlights: \(.highlights | length)",
            "progress: \(((.percent // 0) * 100) | floor)%",
            "tags:", "  - books", "  - highlights",
            "---",
            "%% Written by `lattice books kindle` from KOReader on the Kindle, and rewritten when its highlights change -- edits here are lost. Notes of your own go in [[Books]]. %%",
            "",
            "# \(.title)",
            (if $authors != "" then "*\($authors)*" else empty end),
            (.highlights | sort_by(.datetime // "") | group_by(.chapter // "")
              | sort_by(.[0].datetime // "")[]
              | ("", (if .[0].chapter then "## \(.[0].chapter)" else "## Highlights" end)),
                (.[] | "", "> \(.text | md)",
                  (if (.note // "") != "" then ">", "> **Note:** \(.note | md)" else empty end),
                  "",
                  ([(if .page then "p. \(.page)" else empty end),
                    (if .datetime then .datetime[0:10] else empty end)] | join(" · "))))
          ' <<<"$json" >"$tmp/note.md"
          cmp -s "$tmp/note.md" "$vault/$name.md" || cp "$tmp/note.md" "$vault/$name.md"
        done <"$tmp/books.jsonl"

        # The index Books.md already links to, rebuilt from every note here.
        {
          printf -- '---\ntype: area\narea: "[[00_Hobbies]]"\ntags:\n  - books\n  - highlights\n---\n'
          printf '%%%% Written by lattice books kindle. %%%%\n\n'
          for f in "$vault"/*.md; do
            [[ -e $f && $(basename "$f") != 00_Highlights.md ]] || continue
            n=$(sed -n 's/^highlights: //p' "$f" | head -n 1)
            printf -- '- [[%s]] · %s highlight%s\n' "$(basename "$f" .md)" "$n" "$( [[ $n == 1 ]] || echo s)"
          done
        } >"$tmp/index.md"
        grep -q '^- ' "$tmp/index.md" && ! cmp -s "$tmp/index.md" "$vault/00_Highlights.md" && cp "$tmp/index.md" "$vault/00_Highlights.md"
        rm -rf "$tmp"

        after=$(counted)
        echo $((after > before ? after - before : 0))
      }

      # KOReader's statistics database, posted the way koinsight.koplugin posts it on
      # sleep: /api/plugin/import, under the Kindle's own device id from KOReader's
      # settings. KoInsight upserts per device on (book, page, start time), so sending what
      # the plugin already sent adds nothing. Not /api/upload -- that files everything under
      # a "Manual Upload" device and doubles every page visit the plugin already had.
      stats() {
        local db=$kindle/koreader/settings/statistics.sqlite3 settings=$kindle/koreader/settings.reader.lua
        local id tmp rc=0
        [[ -s $db ]] || return 1
        id=$(sed -n 's/^ *\["device_id"\] = "\([0-9A-Fa-f]*\)",$/\1/p' "$settings" | head -n 1)
        [[ -n $id ]] || { echo "lattice-books: no device_id in $settings" >&2; return 1; }
        tmp=$(mktemp -d)
        # A copy first, so a half-flushed file is never read.
        cp "$db" "$tmp/stats.sqlite3"
        sqlite3 -json "$tmp/stats.sqlite3" \
          'SELECT id, md5, title, authors, series, language, last_open, pages, notes,
                  highlights, total_read_pages, total_read_time FROM book' >"$tmp/books.json"
        sqlite3 -json "$tmp/stats.sqlite3" \
          'SELECT b.md5 AS book_md5, p.page, p.start_time, p.duration, p.total_pages
             FROM page_stat_data p JOIN book b ON b.id = p.id_book' >"$tmp/stats.json"
        # 0.2.0 is the only plugin version this KoInsight accepts; the field is a gate,
        # not a description of this script.
        jq -n --arg id "$id" --slurpfile b "$tmp/books.json" --slurpfile s "$tmp/stats.json" \
          '{version: "0.2.0", books: ($b[0] // []),
            stats: [($s[0] // [])[] | .device_id = $id]}' >"$tmp/body.json"
        curl -fsS --max-time 20 -o /dev/null -H 'Content-Type: application/json' \
          -d "$(jq -nc --arg id "$id" '{version: "0.2.0", id: $id, model: "Kindle"}')" \
          "$koinsight/api/plugin/device" || rc=1
        ((rc)) || curl -fsS --max-time 60 -o /dev/null -H 'Content-Type: application/json' \
          --data-binary "@$tmp/body.json" "$koinsight/api/plugin/import" || rc=1
        rm -rf "$tmp"
        return $rc
      }

      # What lattice-books-kindle.service runs when the Kindle mounts.
      kindle() {
        mountpoint -q "$kindle" || die "the Kindle isn't mounted at $kindle"
        local new statsmsg body bytes
        notify "Kindle connected" "Syncing highlights and statistics…"
        new=$(highlights)
        if stats; then statsmsg="Statistics sent to KoInsight"; else statsmsg="KoInsight didn't take the statistics"; fi
        signal

        body="$new new highlight$( ((new == 1)) || echo s) in the vault · $statsmsg"
        bytes=$(junk | du -cb --files0-from=- 2>/dev/null | tail -n 1 | cut -f 1 || echo 0)
        if ((bytes > 1048576)); then
          local action
          action=$(notify-send -a Books -i accessories-ebook-reader -t 60000 \
            -h string:x-canonical-private-synchronous:lattice-books -A default=Clean \
            "Kindle synced" "$body"$'\n'"Click to delete $(numfmt --to=iec "$bytes") of crash dumps and Mac leftovers first. It ejects in a minute either way." || true)
          [[ $action == default ]] && clean >/dev/null
        fi
        eject
        notify "Kindle synced and ejected" "$body"
      }

      # --- The pill -----------------------------------------------------------------------

      # Hidden only when KoInsight can't be reached at all. The streak counts local days
      # with any page turned, up to today -- or up to yesterday, while today still has time.
      bar() {
        local books st
        if ! books=$(curl -fsS --max-time 4 "$koinsight/api/books") \
          || ! st=$(curl -fsS --max-time 4 "$koinsight/api/stats"); then
          printf '{"text":"","tooltip":"KoInsight unreachable","class":"offline"}\n'
          return
        fi
        # As files rather than --argjson: every page turn is a row in the stats, which
        # outgrows the argument limit after a few months of reading.
        jq -nc --slurpfile b <(printf '%s' "$books") --slurpfile s <(printf '%s' "$st") \
          --arg today "$(date +%F)" \
          --arg yesterday "$(date -d yesterday +%F)" '
          $b[0] as $books | $s[0] as $st
          | def day: . / 1000 | floor | strflocaltime("%Y-%m-%d");
          def prev: (. + "T12:00:00Z" | fromdate) - 86400 | strftime("%Y-%m-%d");
          ([$st.stats[] | .start_time | day] | unique) as $days
          | def run($d): if any($days[]; . == $d) then 1 + run($d | prev) else 0 end;
          ([$st.stats[] | select((.start_time | day) == $today) | .duration] | add // 0) as $secs
          | (if any($days[]; . == $today) then $today else $yesterday end | run(.)) as $streak
          | (any($days[]; . == $today)) as $read_today
          | ($books | max_by(.last_open // 0)) as $b
          | ($days | last) as $last
          | {
              text: ("󰂺" + (if $streak > 0 then " \($streak)" else "" end)),
              tooltip: ([
                (if $b then "\($b.title)" + (if ($b.authors // "") != "" then " · \($b.authors)" else "" end)
                  + "\n\((100 * ($b.unique_read_pages // 0) / ([$b.total_pages // 1, 1] | max)) | floor)% read"
                 else "No books in KoInsight" end),
                (if $streak > 0 then "\($streak)-day streak" else "No streak" end)
                  + (if $secs > 0 then " · \($secs / 60 | floor) min today" else "" end),
                (if $last then "Last read \($last)" else empty end)
              ] | join("\n")),
              class: (if $read_today then "today" elif $streak > 0 then "pending" else "idle" end)
            }'
      }

      open() {
        PATH=$(systemctl --user show-environment | sed -n 's/^PATH=//p')
        export PATH
        exec uwsm app -- xdg-open "$1"
      }

      case ''${1-} in
      add) shift; add "$@" ;;
      kindle) kindle ;;
      clean) clean ;;
      eject) eject ;;
      stats) open "$koinsight" ;;
      library) open "$abs" ;;
      bar) bar ;;
      downloads) downloads ;;
      offer) offer "$2" ;;
      signal) signal ;;
      *)
        echo "usage: lattice-books [add [--force] <file>...|kindle|clean|eject|stats|library]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  options.lattice.books = {
    audiobookshelf = lib.mkOption {
      type = lib.types.str;
      default = "http://labpi8:13378";
      description = ''
        Audiobookshelf, with no trailing slash. The tailnet name, so adding a book works
        away from home too; the Kindle itself reaches the catalogue on the LAN address.
      '';
    };
    koinsight = lib.mkOption {
      type = lib.types.str;
      default = "http://labpi8:3000";
      description = "KoInsight, with no trailing slash. Its API has no authentication.";
    };
    library = lib.mkOption {
      type = lib.types.str;
      default = "books";
      description = "The Audiobookshelf library books are added to, by name.";
    };
    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = config.sops.secrets.abs-token.path;
      description = ''
        A file holding one Audiobookshelf API key. The default is the sops secret
        `abs-token`; mint one under Settings → API Keys, for the root user, with no expiry.
      '';
    };
    refreshCatalog = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 pi8@labpi8 docker restart opds-abs";
      description = ''
        A command that empties abs-opds' hour-long cache of the library, run after a book
        is added. Failing only delays the book on the Kindle.
      '';
    };
    highlightsDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Documents/vault/Hobbies/Books/Highlights";
      description = "Where the Kindle's highlights become notes; Books.md links its index.";
    };
  };

  config = {
    # Reading on the Kindle, from KoInsight. A book and the streak in days beside it; the
    # tooltip has the book in progress and today's minutes. Green once something has been
    # read today, peach while a streak is still waiting on today, muted with no streak.
    # KoInsight only hears from the Kindle when it syncs -- on sleep, or when it's plugged
    # in, which signals the bar -- so a slow interval is all the polling it needs. Click
    # opens KoInsight.
    lattice.bar.modules."custom/reading" = {
      section = "group/toggles";
      order = 90;
      settings = {
        exec = "lattice-books bar";
        return-type = "json";
        signal = barSignal;
        interval = 600;
        on-click = "lattice-books stats";
      };
    };

    sops.secrets.abs-token.owner = "winston";

    environment.systemPackages = [ books ];

    # The pill's exec and its click; see the PATH note on waybar.path in bar.nix.
    systemd.user.services.waybar.path = [ books ];

    # The user manager has a mount unit for each mount udiskie makes, so this needs no
    # udev rule: it starts with the mount, once per plug-in.
    systemd.user.services.lattice-books-kindle = {
      description = "Sync the Kindle's highlights and statistics, then eject it";
      wantedBy = [ "run-media-winston-Kindle.mount" ];
      after = [ "run-media-winston-Kindle.mount" ];
      onFailure = [ "lattice-notify-failure@%n.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe books} kindle";
      };
    };

    systemd.user.paths.lattice-books-downloads = {
      description = "Watch ~/Downloads for EPUBs";
      wantedBy = [ "graphical-session.target" ];
      pathConfig.PathChanged = "%h/Downloads";
    };
    systemd.user.services.lattice-books-downloads = {
      description = "Offer new EPUBs in ~/Downloads to the library";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe books} downloads";
      };
    };

    lattice.cli.commands.books = {
      exec = lib.getExe books;
      args = "<add [--force] <file>...|kindle|clean|eject|stats|library>";
      summary = "Books: add to Audiobookshelf, sync and eject the Kindle";
      details = ''
        add      put EPUBs or PDFs into Audiobookshelf; the Kindle sees them over OPDS
        kindle   highlights into the vault, statistics to KoInsight, then eject
                 (runs on its own when the Kindle is plugged in)
        clean    delete crash dumps and macOS leftovers from the mounted Kindle
        stats    open KoInsight
        library  open Audiobookshelf
      '';
      group = "devices";
      launch = [
        {
          label = "Reading stats";
          args = "stats";
          icon = "accessories-ebook-reader";
        }
        {
          label = "Book library";
          args = "library";
          icon = "accessories-ebook-reader";
        }
      ];
    };
  };
}
