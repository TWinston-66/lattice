# lattice's interactive zsh, run from /etc/zshrc ahead of ~/.zshrc, which is left for
# aliases and anything personal. LATTICE_SHELL tells a .zshrc shared with another OS
# that all of this has already happened here.
LATTICE_SHELL=1

# The theme lattice-theme has picked (theme.nix writes these on every theme switch and
# wallpaper pick). Each tool is pointed at its file rather than given the colours, so it
# follows without a new shell: fzf and bat read theirs on every run, starship at every
# prompt, lazygit and btop at launch.
_lattice="$HOME/.cache/lattice"
[[ -r $_lattice/theme.fzf ]] && export FZF_DEFAULT_OPTS_FILE="$_lattice/theme.fzf"
[[ -r $_lattice/starship.toml ]] && export STARSHIP_CONFIG="$_lattice/starship.toml"
[[ -r $_lattice/theme.bat ]] && export BAT_CONFIG_PATH="$_lattice/theme.bat"
if [[ -r $_lattice/theme.lazygit.yml ]]; then
  # lazygit merges the list left to right: your own config.yml first, when there is one.
  _lg="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"
  export LG_CONFIG_FILE="$_lattice/theme.lazygit.yml"
  [[ -r $_lg ]] && LG_CONFIG_FILE="$_lg,$LG_CONFIG_FILE"
  unset _lg
fi
# btop.conf names catppuccin_mocha, and --themes-dir is searched ahead of
# ~/.config/btop/themes, so the generated file of that name there wins.
[[ -r $_lattice/catppuccin_mocha.theme ]] && alias btop="btop --themes-dir $_lattice"

eval "$(fzf --zsh)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

source @autosuggestions@/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# A command that ran 5s or more says so when it finishes, as a desktop notification. foot
# shows it only while its window is out of focus (desktop-notifications.inhibit-when-focused);
# from inside tmux the request goes out through passthrough, which tmux.conf allows. First
# in precmd, to see the command's own exit status before another hook replaces it.
zmodload zsh/datetime
autoload -Uz add-zsh-hook
_lattice_cmd_start=0
_lattice_notify_preexec() {
  _lattice_cmd_start=$EPOCHSECONDS
  _lattice_cmd=${1//[[:cntrl:]]/ }
}
_lattice_notify_precmd() {
  local st=$? elapsed osc e=$'\e'
  ((_lattice_cmd_start)) || return 0
  elapsed=$((EPOCHSECONDS - _lattice_cmd_start))
  _lattice_cmd_start=0
  ((elapsed >= 5)) || return 0
  osc="$e]777;notify;Command finished;${_lattice_cmd[1,80]} (${elapsed}s, exit $st)$e\\"
  [[ -n $TMUX ]] && osc="${e}Ptmux;${osc//$e/$e$e}$e\\"
  printf '%s' "$osc" >/dev/tty
}
add-zsh-hook preexec _lattice_notify_preexec
precmd_functions=(_lattice_notify_precmd $precmd_functions)

# Syntax highlighting in the theme's colours, re-read at any prompt after a switch: the
# styles are looked up as each line is drawn, so it recolours shells already open.
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
typeset -gA ZSH_HIGHLIGHT_STYLES
zmodload -F zsh/stat b:zstat
_lattice_zsh_mtime=0
_lattice_zsh_reload() {
  local mtime
  mtime=$(zstat +mtime "$_lattice/theme.zsh" 2>/dev/null) || return 0
  if [[ $mtime != "$_lattice_zsh_mtime" ]]; then
    _lattice_zsh_mtime=$mtime
    source "$_lattice/theme.zsh"
  fi
}
_lattice_zsh_reload
add-zsh-hook precmd _lattice_zsh_reload
source @syntaxHighlighting@/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
