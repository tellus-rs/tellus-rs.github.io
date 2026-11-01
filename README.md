# tellus.rs

The website of [tellus](https://github.com/tellus-rs/tellus), served at
[tellus.rs](https://tellus.rs) and built with [Zola](https://www.getzola.org).

## Development

You need Zola 0.23 or later and [just](https://just.systems).

```shell
git clone --recurse-submodules git@github.com:tellus-rs/tellus-rs.github.io.git
just serve   # serve with live reload on all interfaces, port 1111
just all     # check links and build into public/
```

## Code samples

The site shows code from compiled tellus examples and tests, so it cannot drift from the API. Two
components in `templates/components.html` read a file from the `tellus` submodule, optionally only
the region between `// ANCHOR: name` and `// ANCHOR_END: name`, with the indentation of its first
line removed from every line:

```jinja
{{<example path="tellus/examples/tutorials/getting_started/01_hello.rs"/>}}
{{<example path="tellus/examples/tutorials/getting_started/04_watch.rs" anchor="receive"/>}}
{{<code path="tellus/tellus/examples/how_to/device.toml" lang="toml" title="a device's configuration"/>}}
```

`example` is for the docs and takes a path relative to the submodule root. `code` takes a path
relative to the site root and a title, which the landing page uses.

The submodule is pinned to the latest tellus release, so the docs match the crate on crates.io.
The version on the landing page is read from the submodule. So is the release tag which
`{{<tellus_tag/>}}` renders, for example in `git clone --branch {{<tellus_tag/>}}`.

A daily workflow (`pin-tellus.yml`) notices a new `tellus-v*` tag and pins it on the branch
`pin/<tag>`. It then opens a draft pull request listing every tellus change since the last pin. It
needs "Allow GitHub Actions to create and approve pull requests" in the repository's Actions
settings. Before the pull request is marked ready, every listed change is reviewed for statements
on the site which it makes false, with the `update-site-docs` skill in `.claude/skills`.

To pin by hand, without the pull request:

```shell
just pin-tellus tellus-v0.4.0
```

The landing page shows one snippet which does not come from tellus: the `cargo add` commands in
`snippets/install.sh`, see [its README](snippets/README.md).

## Styles

`sass/main.scss` only imports the Sass partials in `sass/`, in an order that matters for the
cascade. Most partials hold the site-wide design: `_fonts`, `_tokens` (colors, font stacks, type
scale), `_base`, `_header`, `_hero`, `_sections`, `_footer`, `_highlight`, `_docs`, `_articles` and
`_copy`. The remaining ones style the landing page (`_borehole`, `_landing`, `_start`) and mark
unreleased features (`_unreleased`).

## llms.txt

`static/llms.txt` lists every docs page for agents, following [llmstxt.org](https://llmstxt.org).
`just check-llms`, also run in CI, fails when a docs page is missing from it or when it links a
page which does not exist.

## Articles

The landing page lists the posts tagged `tellus` from the Atom feed of
[heikoseeberger.de](https://heikoseeberger.de), configured under `[extra.articles]` in `zola.toml`.
The feed is read at build time. If it cannot be loaded, the section shows a link to the blog
instead.

## Deployment

Every push to `main` is checked, built and deployed to GitHub Pages. A daily scheduled run does the
same and picks up new articles. Pull requests are only checked and built.

The site is served at the custom domain `tellus.rs`, configured in the repository's Pages settings.
It is built for `https://tellus.rs` unless the repository variable `BASE_URL` overrides it, for
example to build for another host.

## License

The site content and code are licensed under the
[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html). The fonts in
`static/fonts` are licensed under the SIL Open Font License, see `static/fonts/licenses`.
