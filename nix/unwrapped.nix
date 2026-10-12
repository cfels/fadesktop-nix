{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  cmake,
  ninja,
  clang,
  python3,
  qtbase,
  qtsvg,
  qtwayland,
  qtshadertools,
  kcoreaddons,
  lz4,
  xxhash,
  ffmpeg_6,
  protobuf,
  openal-soft,
  minizip-ng-compat,
  range-v3,
  tl-expected,
  hunspell,
  gobject-introspection,
  rnnoise,
  microsoft-gsl,
  boost,
  ada,
  tdlib,
  tg_owt,
  pango,
  tlottie
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "fagram-desktop-unwrapped";
  version = "2.6.0";

  src = fetchFromGitHub {
    owner = "fagramdesktop";
    repo = "fadesktop";
    rev = "9583c5e8fbe845121e1aa9e57543e60b243fa432";
    fetchSubmodules = true;
    hash = "sha256-/VUUk7wyHv2RS75rQntmXE7OCAdEGqsgv0caXjbTptE=";
  };

  nativeBuildInputs = [
    pkg-config
    cmake
    ninja
    python3
    qtshadertools
    clang
    gobject-introspection
  ];

  buildInputs = [
    pango
    qtbase
    qtsvg
    lz4
    xxhash
    ffmpeg_6
    openal-soft
    minizip-ng-compat
    range-v3
    tl-expected
    rnnoise
    tg_owt
    microsoft-gsl
    boost
    ada
    (tdlib.override { tde2eOnly = true; })
    protobuf
    qtwayland
    kcoreaddons
    hunspell
    tlottie
  ];

  dontWrapQtApps = true;

  cmakeFlags = [
    (lib.cmakeFeature "TDESKTOP_API_ID" "37535655")
    (lib.cmakeFeature "TDESKTOP_API_HASH" "3c6cd55d00180f7439bc2edf391306cf")
    (lib.cmakeBool "DESKTOP_APP_DISABLE_AUTOUPDATE" true)
    (lib.cmakeBool "DESKTOP_APP_USE_PACKAGED" true)
  ];

  meta = with lib; {
    mainProgram = "fagram";
    description = "FAgram Desktop — unofficial TG desktop client (with some nice feature's)";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    homepage = "https://github.com/fagramdesktop/fadesktop";
  };
})
