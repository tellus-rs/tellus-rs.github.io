set shell := ["bash", "-uc"]

serve:
    zola serve --interface 0.0.0.0 --base-url /

build:
    zola build

check:
    zola check

# Run after `build`, which generates the sitemap the check reads.
check-llms:
    scripts/check-llms.sh

all: check build check-llms

# Pin the tellus submodule to a release tag, e.g. `just pin-tellus tellus-v0.3.2`.
pin-tellus tag:
    git -C tellus fetch --tags
    git -C tellus checkout {{ tag }}
    git add tellus
