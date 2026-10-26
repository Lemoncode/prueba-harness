# Import Knowledge — formatting a staging directory

How to run the project's formatter on a staging directory under `.lemony/import/`.
The [`import-knowledge`](.claude/skills/import-knowledge/SKILL.md) and
[`convention-iterate`](.claude/skills/convention-iterate/SKILL.md) skills send you here
when the project has a formatter; everything they say still holds.

`rules apply` lands each staged file byte for byte, so a staged file is final only once
the project's formatter has run on it. Otherwise the commit that follows fails a CI
that checks formatting, and the size `rules measure` reported is not the size that
lands: formatting pads a markdown table, so a rule measured under the cap can land over
it.

What gets formatted is the staged markdown, every `.md` file but `plan.md`, each as the
file it becomes: `rules/<p>` as `.claude/rules/<p>`, `skills/<p>` as
`.claude/skills/<p>`, `reference/<p>` as `docs/reference/<p>`. A skill's other files
(scripts, JSON, YAML) travel unchanged: a formatter cannot parse some of them, and
replacing a file can drop a script's executable bit. A formatter that does not format
markdown (biome) leaves nothing to do here.

Run this one command from the repository root, with `<staging dir>` filled in and the
formatter line swapped for the project's (`dprint fmt --stdin "$target"` for dprint):

```sh
S='<staging dir>'
S=${S%/}
T=$(mktemp)
find "$S" -name '*.md' ! -path "$S/plan.md" | while IFS= read -r f; do
  rel=${f#"$S"/}
  case $rel in
    rules/*|skills/*) target=.claude/$rel ;;
    reference/*) target=docs/$rel ;;
    *) continue ;;
  esac
  node_modules/.bin/prettier --stdin-filepath "$target" < "$f" > "$T" && [ -s "$T" ] && cat "$T" > "$f"
done
rm -f "$T"
```

Each part answers a way the obvious form fails, in bash and zsh alike:

- The text goes in on stdin with the target path. Given the staging path, the
  formatter skips the file, because the staging directory is gitignored and formatters
  skip ignored files even when the command names them; prettier still reports success.
  Through stdin, the project's settings for the target path (prettier's `overrides`
  and `.prettierignore`) apply.
- The output goes to a temporary file and is copied back only when the formatter
  exited 0 and printed something. Redirecting onto the staged file itself empties it
  before the formatter reads it, and prettier prints nothing for a file it cannot
  handle (exiting non-zero, or 0 with `--ignore-unknown`).
- `find … | while read` reaches nested files and names with spaces; `**` without
  bash's `globstar` and an unquoted `$(find …)` miss some. A loop variable named
  `path` would replace zsh's `PATH`.

It is one command so the human is asked once per formatting run, not once per file.
Its output is the project's formatting, not new wording. If the formatter cannot run
at all, say so in your report: the files land unformatted.

Format after every change to a staged file and before every `rules measure`, so the
numbers it reports are those of the text that lands.
