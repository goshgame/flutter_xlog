#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SUPPORTED_TOKENS = {
    "year": ('%d', '1900 + tm.tm_year'),
    "month": ('%02d', '1 + tm.tm_mon'),
    "day": ('%02d', 'tm.tm_mday'),
    "hour": ('%02d', 'tm.tm_hour'),
    "minute": ('%02d', 'tm.tm_min'),
    "second": ('%02d', 'tm.tm_sec'),
    "millisecond": ('%03ld', 'static_cast<long>(_info->timeval.tv_usec / 1000)'),
    "microsecond": ('%06ld', 'static_cast<long>(_info->timeval.tv_usec)'),
    "timezone": ('%s', 'timezone_offset'),
}

HEADER_START = "// GOSH_XLOG_TIME_HELPER_BEGIN"
HEADER_END = "// GOSH_XLOG_TIME_HELPER_END"
BLOCK_START = "// GOSH_XLOG_TIME_PATCH_BEGIN"
BLOCK_END = "// GOSH_XLOG_TIME_PATCH_END"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Patch Mars formatter.cc timestamp format.")
    parser.add_argument("--formatter", required=True, help="Path to mars/xlog/src/formater.cc")
    parser.add_argument("--config", required=True, help="Path to formatter patch config")
    return parser.parse_args()


def load_config(path: Path) -> dict[str, str]:
    config: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"invalid config line: {raw_line}")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        config[key] = value
    return config


def build_format_parts(template: str) -> tuple[str, list[str], bool]:
    pattern = re.compile(r"\{([a-z_]+)\}")
    position = 0
    pieces: list[str] = []
    args: list[str] = []
    needs_timezone = False

    for match in pattern.finditer(template):
        literal = template[position:match.start()]
        if literal:
            pieces.append(escape_printf_literal(literal))

        token = match.group(1)
        if token not in SUPPORTED_TOKENS:
            raise ValueError(f"unsupported timestamp token: {{{token}}}")

        fmt, expr = SUPPORTED_TOKENS[token]
        pieces.append(fmt)
        args.append(expr)
        if token == "timezone":
            needs_timezone = True
        position = match.end()

    tail = template[position:]
    if tail:
        pieces.append(escape_printf_literal(tail))

    return "".join(pieces), args, needs_timezone


def escape_printf_literal(value: str) -> str:
    return value.replace("%", "%%").replace("\\", "\\\\").replace('"', '\\"')


def indent_lines(lines: list[str], indent: str) -> str:
    return "\n".join(f"{indent}{line}" if line else "" for line in lines)


def build_helper_block(needs_timezone: bool) -> str:
    if not needs_timezone:
        return ""

    lines = [
        HEADER_START,
        "namespace {",
        "void format_timezone_offset(long offset_seconds, char* output, size_t output_size) {",
        "    const char sign = offset_seconds >= 0 ? '+' : '-';",
        "    const long abs_seconds = std::labs(offset_seconds);",
        "    const long total_minutes = abs_seconds / 60;",
        "    const long hours = total_minutes / 60;",
        "    const long minutes = total_minutes % 60;",
        "",
        '    snprintf(output, output_size, "%c%02ld:%02ld", sign, hours, minutes);',
        "}",
        "}  // namespace",
        HEADER_END,
    ]
    return "\n".join(lines)


def build_time_block(template: str) -> str:
    fmt_string, args, needs_timezone = build_format_parts(template)

    lines = [
        BLOCK_START,
        "char temp_time[128] = {0};",
    ]

    if needs_timezone:
        lines.append("char timezone_offset[8] = {0};")

    lines.extend(
        [
            "",
            "if (0 != _info->timeval.tv_sec) {",
            "    time_t sec = _info->timeval.tv_sec;",
            "    tm tm = *localtime((const time_t*)&sec);",
            "",
            "#ifdef ANDROID",
        ]
    )

    if needs_timezone:
        lines.append("    format_timezone_offset(tm.tm_gmtoff, timezone_offset, sizeof(timezone_offset));")

    lines.extend(
        [
            "    snprintf(temp_time,",
            "             sizeof(temp_time),",
            f'             "{fmt_string}",',
        ]
    )
    lines.extend(build_argument_lines(args))
    lines.extend(
        [
            "#elif _WIN32",
        ]
    )

    if needs_timezone:
        lines.append("    format_timezone_offset(-_timezone, timezone_offset, sizeof(timezone_offset));")

    lines.extend(
        [
            "    snprintf(temp_time,",
            "             sizeof(temp_time),",
            f'             "{fmt_string}",',
        ]
    )
    lines.extend(build_argument_lines(args))
    lines.extend(
        [
            "#else",
        ]
    )

    if needs_timezone:
        lines.append("    format_timezone_offset(tm.tm_gmtoff, timezone_offset, sizeof(timezone_offset));")

    lines.extend(
        [
            "    snprintf(temp_time,",
            "             sizeof(temp_time),",
            f'             "{fmt_string}",',
        ]
    )
    lines.extend(build_argument_lines(args))
    lines.extend(
        [
            "#endif",
            "}",
            BLOCK_END,
        ]
    )

    return indent_lines(lines, "        ")


def build_argument_lines(args: list[str]) -> list[str]:
    if not args:
        return ["             0);"]

    lines: list[str] = []
    for index, arg in enumerate(args):
        suffix = "," if index < len(args) - 1 else ");"
        lines.append(f"             {arg}{suffix}")
    return lines


def replace_helper_block(source: str, helper_block: str) -> str:
    marker_pattern = re.compile(
        rf"\n[ \t]*{re.escape(HEADER_START)}.*?[ \t]*{re.escape(HEADER_END)}\n",
        re.S,
    )
    if marker_pattern.search(source):
        replacement = f"\n{helper_block}\n" if helper_block else "\n"
        return marker_pattern.sub(replacement, source, count=1)

    legacy_pattern = re.compile(
        r"\n[ \t]*namespace \{\n[ \t]*void format_timezone_offset\(.*?\n[ \t]*\}  // namespace\n",
        re.S,
    )
    if legacy_pattern.search(source):
        replacement = f"\n{helper_block}\n" if helper_block else "\n"
        return legacy_pattern.sub(replacement, source, count=1)

    anchor = "namespace mars {\nnamespace xlog {\n"
    if helper_block:
        return source.replace(anchor, f"{anchor}\n{helper_block}\n", 1)
    return source


def replace_time_block(source: str, time_block: str) -> str:
    marker_pattern = re.compile(
        rf"^[ \t]*{re.escape(BLOCK_START)}.*?^[ \t]*{re.escape(BLOCK_END)}[ \t]*\n?",
        re.S | re.M,
    )
    if marker_pattern.search(source):
        return marker_pattern.sub(f"{time_block}\n", source, count=1)

    legacy_pattern = re.compile(
        r"^[ \t]*char temp_time\[(?:64|128)\] = \{0\};.*?^[ \t]*\}\n(?=\n[ \t]*// _log\.AllocWrite)",
        re.S | re.M,
    )
    if not legacy_pattern.search(source):
        raise ValueError("failed to locate formatter time block")
    return legacy_pattern.sub(f"{time_block}\n", source, count=1)


def main() -> int:
    args = parse_args()
    formatter_path = Path(args.formatter)
    config_path = Path(args.config)

    if not formatter_path.is_file():
        print(f"formatter file not found: {formatter_path}", file=sys.stderr)
        return 1
    if not config_path.is_file():
        print(f"config file not found: {config_path}", file=sys.stderr)
        return 1

    config = load_config(config_path)
    template = config.get("TIMESTAMP_FORMAT")
    if not template:
        print("TIMESTAMP_FORMAT is required", file=sys.stderr)
        return 1

    _, _, needs_timezone = build_format_parts(template)
    helper_block = build_helper_block(needs_timezone)
    time_block = build_time_block(template)

    source = formatter_path.read_text()
    source = replace_helper_block(source, helper_block)
    source = replace_time_block(source, time_block)

    formatter_path.write_text(source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
