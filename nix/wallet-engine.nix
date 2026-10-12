{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
}:

let
  src = fetchFromGitHub {
    owner = "i582";
    repo = "wallet-engine";
    rev = "e59e0d89d7ee90c388bf36e3334c5b276f396697";
    hash = "sha256-729W7YCjkUCdL8Xk8BPHKdjpK6F+x1C9wnk/17TGhx4=";
  };

  bindgen = rustPlatform.buildRustPackage {
    pname = "wallet-engine-bindgen";
    version = "0.9.0";
    inherit src;
    cargoRoot = "bindgen/cpp";
    buildAndTestSubdir = "bindgen/cpp";
    cargoHash = "sha256-n3VKg3OMU9a4fbaxISWKEVXRe9vRe63/GeRdpmDEZTM=";
  };
in
rustPlatform.buildRustPackage {
  pname = "wallet-engine";
  version = "0.0.7";
  inherit src;

  patches = [
    (fetchurl {
      url = "https://raw.githubusercontent.com/desktop-app/patches/aec474953ff7ee9b6e4cd9b8658288ea86d124f3/wallet-engine.patch";
      hash = "sha256-tAq6gsOaQtBSaoXs+kDWE7qlexotZgDmAaQqFXazuCI=";
    })
  ];

  cargoHash = "sha256-b9LErZRUgVa/bHjmbN3ltW8vUoF9UhCjMAfFPSbpzbY=";
  cargoBuildFlags = [
    "-p"
    "wallet-engine"
  ];
  # Integration suites require external TON network tools and services.
  cargoTestFlags = [
    "-p"
    "wallet-engine"
    "--lib"
  ];
  nativeBuildInputs = [ bindgen ];

  postInstall = ''
    mkdir -p "$out/include/wallet_engine"
    uniffi-bindgen-cpp --library \
      --out-dir "$out/include/wallet_engine" \
      "$out/lib/libwallet_engine.so"
  '';

  passthru = { inherit bindgen; };

  meta = {
    description = "TON wallet engine with C++ bindings";
    homepage = "https://github.com/i582/wallet-engine";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = lib.platforms.linux;
  };
}
