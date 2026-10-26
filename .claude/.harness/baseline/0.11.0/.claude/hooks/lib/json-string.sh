#!/usr/bin/env bash
# JSON string encoding for the SessionStart hooks' replies — sourced by
# `init.sh` (the blocking reply) and `entry-protocol.sh` (the protocol as
# `additionalContext`). Claude Code reads a hook's stdout as JSON only when it
# is nothing else, and jq is not a dependency of the boot path, so the encoding
# lives here, once.
#
# `json_string` reads stdin and prints it as one JSON string, quotes included:
# `\` and `"` escaped, line breaks as `\n`, tab and carriage return as `\t` and
# `\r`, every other control byte as `\u00XX`. Byte-wise under LC_ALL=C; bytes
# from 0x80 up pass through, so UTF-8 text stays UTF-8. A trailing line break
# is dropped (awk reads lines).

json_string() {
  LC_ALL=C awk '
    BEGIN {
      for (i = 1; i < 32; i++) esc[sprintf("%c", i)] = sprintf("\\u%04x", i)
      esc["\t"] = "\\t"; esc["\r"] = "\\r"
      esc["\\"] = "\\\\"; esc["\""] = "\\\""
    }
    {
      line = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        line = line ((c in esc) ? esc[c] : c)
      }
      out = (NR == 1) ? line : out "\\n" line
    }
    END { printf "\"%s\"", out }
  '
}
