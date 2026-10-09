# VA-API driver for V4L2 stateless decoders, with support for the Apple Video Decoder.
#
# The kernel side already works here: the avd driver probes, loads Asahi's firmware and
# exposes /dev/video0 and /dev/video1. But AVD is a stateless decoder, and almost nothing on
# the desktop speaks that (ffmpeg's v4l2m2m decoders are stateful and never negotiate with
# it), so without this shim nothing can drive the device and every video decodes on the CPU.
#
# This is iconidentify's fork, at the commit Omarchy Mac pins (omacom/omarchy-mac,
# joelrb/omarchy-pkgs-aarch64). It is megi's driver plus sofus13's AVD support and the
# fixes sofus13's repo never took: Chromium-style pre-exported surfaces (which showed as
# solid green video), H.264 multi-slice hangs, HEVC slice headers and 10-bit surfaces.
# Neither nixpkgs nor the AUR has it. A bump means changing rev and hash together.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  libva,
  libdrm,
  python3,
}:
stdenv.mkDerivation {
  pname = "libva-v4l2-request";
  version = "1.3.r11-unstable-2026-09-19";

  src = fetchFromGitHub {
    owner = "iconidentify";
    repo = "libva-v4l2_request";
    rev = "5b5046cbda6892f4a63df0015857a80bd42c17cf";
    hash = "sha256-7AEijheNbaEjecQnRrAQ1MmQV23BFFLTsFMnaG1ji3Y=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];
  buildInputs = [
    libva
    libdrm
  ];

  # The offline suite: parser fuzz seeds and decode cases against an intercepted device,
  # none of which need /dev/video*.
  doCheck = true;
  nativeCheckInputs = [ python3 ];

  # Except the ThreadSanitizer pass. TSan has no mapping for the 47-bit address space of
  # Asahi's 16K-page kernel ("unsupported VMA range ... Found 47 - Supported 39, 42 and 48"),
  # and the script's own skip-on-unsupported probe misses that case, so it fails rather
  # than skipping. 77 is meson's skip code.
  postPatch = ''
    echo 'exit 77' > tests/concurrent-tsan.sh
  '';

  # libva's pkg-config driverdir is inside libva's own store path; the driver goes in this
  # package's lib/dri, which hardware.graphics.extraPackages links into
  # /run/opengl-driver/lib/dri.
  mesonFlags = [ "-Ddriverdir=${placeholder "out"}/lib/dri" ];

  # libva picks its driver from the DRM name of the render node, which is "asahi" here, so
  # it looks for asahi_drv_video.so. Mesa ships no VA driver under that name, so the alias
  # makes every VA-API app find the decoder with no LIBVA_DRIVER_NAME in the environment.
  postInstall = ''
    ln -s v4l2_request_drv_video.so $out/lib/dri/asahi_drv_video.so
  '';

  meta = {
    description = "VA-API driver for V4L2 stateless decoders, with Apple Video Decoder support";
    homepage = "https://github.com/iconidentify/libva-v4l2_request";
    license = lib.licenses.gpl3Plus;
    platforms = [ "aarch64-linux" ];
  };
}
