#! /bin/bash

# abort on all errors
set -eo pipefail

if [ "$DEBUG" != "" ]; then
    set -x
fi

script=$(readlink -f "$0")

show_usage() {
    echo "Usage: $script --appdir <path to AppDir>"
    echo
    echo "Creates a portable Perl environment in an AppDir"
    echo
    echo "Variables:"
    echo "  CPAN_PACKAGES=\"packageA;packageB;...\""
    echo "  PERL_VERSION=\"5.34.0.0\""
    echo "  LINUXDEPLOY=.../linuxdeploy-x86_64.AppImage"
}

_isterm() {
    tty -s && [[ "$TERM" != "" ]] && tput colors &>/dev/null
}

log() {
    _isterm && tput setaf 3
    _isterm && tput bold
    echo -*- "$@"
    _isterm && tput sgr0
    return 0
}

APPDIR=

while [ "$1" != "" ]; do
    case "$1" in
        --plugin-api-version)
            echo "0"
            exit 0
            ;;
        --appdir)
            APPDIR="$2"
            shift
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log "Invalid argument: $1"
            log
            show_usage
            exit 1
            ;;
    esac
done

if [ "$APPDIR" == "" ]; then
    show_usage
    exit 1
fi

if [[ "$LINUXDEPLOY" == "" ]]; then
    echo "Error: \$LINUXDEPLOY not set"
    show_usage
    exit 1
fi

# make path absolute
LINUXDEPLOY="$(readlink -f "$LINUXDEPLOY")"
export LINUXDEPLOY

mkdir -p "$APPDIR"

if [ "$CPAN_PACKAGES" == "" ]; then
    log "WARNING: \$CPAN_PACKAGES not set, no packages will be installed!"
fi

# the user can specify a directory into which the relocatable perl archive is downloaded
# if they don't specify one, we use a temporary directory with a predictable name to preserve downloaded files across runs
# this should reduce the download overhead
# if one is specified, the installer will not be re-downloaded unless it has changed
if [ "$PERL_DOWNLOAD_DIR" != "" ]; then
    # resolve path relative to cwd
    if [[ "$PERL_DOWNLOAD_DIR" != /* ]]; then
        PERL_DOWNLOAD_DIR="$(readlink -f "$PERL_DOWNLOAD_DIR")"
    fi

    log "Using user-specified download directory: $PERL_DOWNLOAD_DIR"
else
    # create temporary directory into which downloaded files are put
    PERL_DOWNLOAD_DIR="/tmp/linuxdeploy-plugin-perl-$(id -u)"

    log "Using default temporary download directory: $PERL_DOWNLOAD_DIR"
fi

# make sure the directory exists
mkdir -p "$PERL_DOWNLOAD_DIR"

if [ -d "$APPDIR"/usr/perl ]; then
    log "WARNING: perl prefix directory exists: $APPDIR/usr/perl"
    log "Please make sure you perform a clean build before releases to make sure your process works properly."
fi

ARCH="${ARCH:-x86_64}"

# install relocatable-perl, a self contained Perl distribution, into AppDir
case "$ARCH" in
    "x86_64")
        perl_archive_filename=perl-x86_64-linux.tar.gz
        ;;
    *)
        log "ERROR: Unsupported Perl arch: $ARCH"
        exit 1
        ;;
esac

# use latest release unless the user wants a specific release
if [[ "$PERL_VERSION" == "" ]]; then
    PERL_VERSION="$(curl -q https://github.com/skaji/relocatable-perl/releases.atom | grep '<title>' | cut -d'>' -f2 | cut -d'<' -f1 | tail -n+2 | head -n1)"
fi

pushd "$PERL_DOWNLOAD_DIR"
    relocatable_perl_url=https://github.com/skaji/relocatable-perl/releases/download/"$PERL_VERSION"/"$perl_archive_filename"

    # let's make sure the file exists before we then rudimentarily ensure mutual exclusive access to it with flock
    # we set the timestamp to epoch 0; this should likely trigger a redownload for the first time
    touch "$perl_archive_filename" -d '@0'

    # now, let's download the file
    flock "$perl_archive_filename" wget -N -c "$relocatable_perl_url"
popd

# install relocatable perl into AppDir
mkdir -p "$APPDIR"/usr
tar xfv "$PERL_DOWNLOAD_DIR"/"$perl_archive_filename" --strip-components=1 -C "$APPDIR"/usr

# we don't want to touch the system, therefore using a temporary home
temp_home="$(readlink -f _temp_home)"
mkdir -p "$temp_home"
export HOME="$temp_home"
#_cleanup_temp_home() {
#    [[ -d "$temp_home" ]] && rm -rf "$temp_home"
#}
#trap _cleanup_temp_home EXIT

# make sure cpan doesn't ask questions
#export PERL_MM_USE_DEFAULT=1

# install packages specified via $CPAN_PACKAGES
IFS=';' read -ra pkgs <<< "$CPAN_PACKAGES"
for pkg in "${pkgs[@]}"; do
    # cpanm is easier to use in a headless environment
    # we skip tests, as they might not run inside a container
    "$APPDIR"/usr/bin/cpanm -n "$pkg"
done

# make sure to deploy all new libraries placed in the AppDir by cpanm
so_dirs=()

while IFS= read -r -d $'\0'; do
    so_file="$REPLY"
    so_file_dir="$(readlink -f "$(dirname "$so_file")")"

    known=0
    for i in "${so_dirs[@]}"; do
        if [[ "$i" == "$so_file_dir" ]]; then
            known=1
            break
        fi
    done

    if [[ "$known" -eq 0 ]]; then
        so_dirs+=("$so_file_dir")
    fi
done < <(find "$APPDIR"/usr/lib/{site_perl/,}5.*/x86_64-linux/ -type f -iname '*.so*' -print0)

extra_args=()
for so_dir in "${so_dirs[@]}"; do
    echo ".so files found in $so_dir, deploying with linuxdeploy"
    extra_args+=("--deploy-deps-only" "$so_dir")
done

env LINUXDEPLOY_PLUGIN_MODE=1 "$LINUXDEPLOY" --appdir "$APPDIR" "${extra_args[@]}"
