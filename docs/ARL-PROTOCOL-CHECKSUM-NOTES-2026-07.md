# ARL Protocol Checksum Notes - July 2026

This is the working reverse-engineering log for IMPACT+ result-row acceptance.
It separates trace-confirmed facts from hypotheses and emulator tests.

## Trace-Confirmed Facts

- IMPACT requests a result row with `#rd 246\r`.
- If IMPACT accepts the row, it sends `#em 242\r`.
- If IMPACT rejects the row, it sends `?` and the ARL repeats the result row.
- The result-row checksum observed so far is decimal text at the end of the row.
- Our current checksum calculation matches every captured accepted and rejected
  row: strip an optional leading `#`, sum ASCII bytes of the payload including
  the single separator space before the checksum, then take modulo 256.
- The rejected rows are not serial loss cases. DOSBox-X receives complete rows,
  and the checksums validate under the observed checksum algorithm.

## Current Inventory

Generated from five local traces under `/tmp/arl-traces`.

| run | group | row | outcome | checksum | valid | excerpt |
|---|---:|---:|---|---:|---|---|
| sample-analysis-20260708-145951 | 1 | 1 | accepted | 032 | true | 0.726,0.346,0.224,... |
| sample-analysis-20260708-145951 | 1 | 2 | accepted | 055 | true | 0.291,0.201,0.176,... |
| sample-analysis-20260708-145951 | 1 | 3 | accepted | 061 | true | 2.098,0.618,0.331,... |
| sample-analysis-20260708-145951 | 2 | 4 | rejected | 112 | true | 4.649,0.991,0.365,... |
| sample-analysis-20260708-163002 | 1 | 1 | rejected | 113 | true | 16.884,2.592,0.581,... |
| sample-analysis-20260708-173311 | 1 | 1 | accepted | 001 | true | 47.574,3.678,2.208,... |
| sample-analysis-20260708-173311 | 1 | 2 | accepted | 009 | true | 1.410,0.498,0.291,... |
| sample-analysis-20260708-173311 | 1 | 3 | accepted | 087 | true | 1.593,0.500,0.299,... |
| sample-analysis-20260708-173311 | 2 | 4 | accepted | 080 | true | 1.368,0.429,0.278,... |
| sample-analysis-20260708-173311 | 2 | 5 | accepted | 040 | true | 1.370,0.496,0.291,... |
| sample-analysis-20260708-173311 | 2 | 6 | accepted | 062 | true | 1.381,0.362,0.259,... |
| sample-analysis-20260708-173311 | 2 | 7 | accepted | 036 | true | 0.978,0.317,0.235,... |
| sample-analysis-20260708-173311 | 2 | 8 | rejected | 231 | true | 21.146,2.417,0.590,... |
| sample-analysis-20260708-205041 | 1 | 1 | accepted | 093 | true | 101.371,12.578,2.490,... |
| sample-analysis-20260708-205041 | 1 | 2 | accepted | 024 | true | 96.533,12.455,2.460,... |
| sample-analysis-20260708-205041 | 1 | 3 | accepted | 089 | true | 107.760,13.354,2.630,... |
| sample-analysis-20260708-205041 | 1 | 4 | rejected | 117 | true | 106.251,13.389,2.615,... |
| sample-analysis-20260708-232928 | 1 | 1 | rejected | 196 | true | 2.469,1.103,2.504,... |

Summary:

| checksum range | accepted | rejected |
|---|---:|---:|
| 000-099 | 13 | 0 |
| 100-255 | 0 | 5 |

This is the strongest current signal: every captured accepted result has a
checksum below 100, and every captured rejected result has a checksum of 100 or
higher.

## Hypotheses

### H1: IMPACT result parser has a decimal checksum boundary bug

IMPACT may read or compare only two decimal checksum digits in the result-row
parser. That would allow `001`, `024`, `093`, etc. to pass as values 1, 24, 93,
but reject `112`, `117`, `196`, and `231`.

This can coexist with IMPACT sending three-digit command checksums such as
`#rd 246` because transmit-side command formatting and receive-side result
validation may be different code paths.

### H2: IMPACT expects a two-digit checksum presentation for result rows

If true, rows with checksum 100-255 might need a transformed checksum text such
as the last two decimal digits (`117` -> `17`) or a modulo-100 value. This is
not yet confirmed. It must be tested with the emulator before considering any
real serial filter.

### H3: Textual row shaping can preserve numeric values while lowering checksum

The checksum is over ASCII text, not binary numeric values. If IMPACT parses
numbers normally, leading zeros should not change the numeric result. This lets
us change the checksum without changing chemistry values.

Examples:

| original | shaped equivalent | checksum after shaping |
|---|---|---:|
| `4.649,... 112` | `0004.649,... 000` | 000 |
| `106.251,... 117` | `000106.251,... 005` | 005 |
| `21.146,... 231` | `021.146,... 023` | 023 |

This is only a hypothesis until IMPACT accepts shaped rows in the emulator.

## Emulator Test Plan

Use `95 EMU CHECKSUM SWEEP`, with distinct recovery rows so IMPACT does not
mistake two identical rows for a complete stable sample.

Test cases to confirm:

- Case 01: distinct valid checksum `099` control.
- Case 02: distinct valid checksum `100`.
- Case 03: distinct valid checksum `101`.
- Case 04: distinct payload whose computed checksum is `100`, but whose checksum
  field is presented as `00`.
- Case 05: distinct payload whose computed checksum is `101`, but whose checksum
  field is presented as `01`.
- Case 06: distinct valid checksum `117`.
- Case 07: distinct payload whose computed checksum is `117`, but whose checksum
  field is presented as `17`.
- Case 08: distinct valid checksum `231`.
- Case 09: distinct payload whose computed checksum is `231`, but whose checksum
  field is presented as `31`.
- Case 10: distinct low-checksum `089` control after multiple cases.
- Cases 11-13: distinct low-checksum shaped/control rows with checksums `005`,
  `023`, and `000`.

Acceptance signal:

- `#em 242\r` means IMPACT accepted the row.
- `?` means IMPACT rejected the row.

## Emulator Results

### 2026-07-09 01:47 - `95 EMU CHECKSUM SWEEP`

Run folder: `C:\ARL\diagnostics\impact-emulator-20260709-014719`.

| Case | Payload/checksum test | IMPACT response | Interpretation |
|---|---|---|---|
| 01 | distinct valid checksum `099` | `#em` | Accepted |
| 02 | distinct valid checksum `100` | `?` | Rejected |
| recovery 01 | distinct low checksum `055` | `#em` | Accepted |
| 03 | distinct valid checksum `101` | `?` | Rejected |
| recovery 02 | distinct low checksum `061` | `#em` | Accepted |
| 04 | payload computes to `100`, checksum field sent as `00` | `?` | Rejected; two-digit truncation did not pass |
| recovery 03 | distinct low checksum `040` | `#em` | Accepted |

The run then entered a weird/blank IMPACT state because the emulator matched
`sweep-accepted-end-marker` for `#em 242\r` but returned no bytes. Real traces
show `#em` transitions being acknowledged by the ARL with `#`, so emulator
profiles were updated to return `#` for accepted end-marker rules.

Confirmed from this run:

- Valid decimal `100` and `101` result checksums are rejected by IMPACT.
- Simply truncating `100` to a two-digit checksum field `00` is also rejected.
- Distinct low-checksum recovery rows continue to be accepted, so the rejection
  is still tied to checksum presentation/validation rather than value similarity.

### Next `95` Sweep Revision

The next profile revision uses the early cases for new information instead of
repeating already-settled variants:

| Case | Test |
|---:|---|
| 01 | Low-checksum control `099` |
| 02 | Valid decimal checksum `100` |
| 03 | Valid decimal checksum `101` |
| 04 | Payload computes to 100, checksum field sent as hex `64` |
| 05 | Payload computes to 101, checksum field sent as hex `65` |
| 06 | Payload computes to 100, checksum field sent as single text byte `d` |
| 07 | Distinct shaped/control row with checksum `005` |
| 08 | Distinct shaped/control row with checksum `023` |
| 09 | Distinct shaped/control row with checksum `000` |
| 10 | Valid decimal checksum `117` |
| 11 | Payload computes to 117, checksum field sent as hex `75` |
| 12 | Payload computes to 117, checksum field sent as decimal last two digits `17` |
| 13 | Valid decimal checksum `231` |
| 14 | Payload computes to 231, checksum field sent as hex `E7` |
| 15 | Payload computes to 231, checksum field sent as decimal last two digits `31` |
| 16 | Payload computes to 100, checksum field sent as decimal last two digits `00` |
| 17 | Payload computes to 101, checksum field sent as decimal last two digits `01` |

All case rows and recovery rows use distinct values to avoid triggering IMPACT's
stable/repeated-sample `Store Result?` behavior during the checksum experiment.

### 2026-07-09 01:56 - Revised `95 EMU CHECKSUM SWEEP`

Run folder: `C:\ARL\diagnostics\impact-emulator-20260709-015659`.

The first part of the run had no `no_match` events. The accepted-end-marker and
new-sample fallbacks worked: after an `es 248\r`, IMPACT sent `ns 0,0 173\r`
and the emulator ACKed it, allowing the next analysis group to continue.

| Case | Test | IMPACT response | Interpretation |
|---:|---|---|---|
| 01 | Low-checksum control `099` | `#em` | Accepted |
| 02 | Valid decimal checksum `100` | `?` | Rejected |
| recovery 01 | Low checksum `055` | `#em` | Accepted |
| 03 | Valid decimal checksum `101` | `?` | Rejected |
| recovery 02 | Low checksum `061` | `#em` | Accepted |
| 04 | Payload computes to 100, checksum field sent as hex `64` | `?` | Rejected |
| recovery 03 | Low checksum `040` | `#em` | Accepted |
| 05 | Payload computes to 101, checksum field sent as hex `65` | `?` | Rejected |
| recovery 04 | Low checksum `062` | `#em` | Accepted |
| 06 | Payload computes to 100, checksum field sent as single text byte `d` | `?` | Rejected |
| recovery 05 | Low checksum `093` | `#em` | Accepted |
| 07 | Distinct shaped/control row with checksum `005` | `?` | Rejected |
| recovery 06 | Low checksum `089` | `#em` | Accepted |
| 08 | Distinct shaped/control row with checksum `023` | `#em` | Accepted |
| 09 | Distinct shaped/control row with checksum `000` | `#em` | Accepted |
| 10 | Valid decimal checksum `117` | `?` | Rejected |
| recovery 07 | Low checksum `005` | `?` | Rejected |
| recovery 08 | Low checksum `023` | `#em` | Accepted |
| 11 | Payload computes to 117, checksum field sent as hex `75` | `?` | Rejected |
| recovery 09 | Low checksum `000` | `#em` | Accepted |
| 12 | Payload computes to 117, checksum field sent as decimal last two digits `17` | `?` then `no_match` | Rejected; profile ran out of recovery rows |

New conclusions from this run:

- Hex presentation (`64`, `65`) does not satisfy IMPACT for payloads whose
  computed decimal checksums are 100 and 101.
- A single-character/byte-style presentation (`d`) also does not satisfy IMPACT
  for computed checksum 100.
- Low checksum alone is not sufficient: case 07 with checksum `005` was
  rejected, while recovery/checksum rows `055`, `061`, `040`, `062`, `093`,
  `089`, case 08 `023`, recovery `023`, and recovery `000` were accepted.
- Two-digit decimal truncation is not a general workaround: checksum `17` for a
  payload that computes to `117` was rejected.
- The third-tanda stall was caused by test-profile exhaustion, not by a new
  emulator transport failure: after case 12, IMPACT sent `?`, and the profile
  had no remaining recovery rule.
- This introduces a second suspected validator beyond checksum range: IMPACT may
  also reject some rows based on numeric ranges, field formatting, or alloy
  plausibility. The checksum boundary remains strong, but not exclusive.

### 2026-07-09 02:08 - Full `95 EMU CHECKSUM SWEEP`

Run folder: `C:\ARL\diagnostics\impact-emulator-20260709-020832`.

This run consumed all 17 sweep cases and stopped only because IMPACT requested
another `#rd 246\r` after the profile had no `case18`. The final `no_match` is
therefore expected profile exhaustion, not a transport failure.

The run also produced `LPTCAP.PRN` (`42136` bytes), confirming that IMPACT
reached store/print flows during the emulator sweep.

| Case | Test | IMPACT response | Recovery |
|---:|---|---|---|
| 01 | Low checksum `099` | `#em` | Direct accept |
| 02 | Valid decimal checksum `100` | `?` | `055` accepted |
| 03 | Valid decimal checksum `101` | `?` | `061` accepted |
| 04 | Hex `64` for computed `100` | `?` | `040` accepted |
| 05 | Hex `65` for computed `101` | `?` | `062` accepted |
| 06 | Text byte `d` for computed `100` | `?` | `093` accepted |
| 07 | Low checksum `005` | `?` | `089` accepted |
| 08 | Low checksum `023` | `#em` | Direct accept |
| 09 | Low checksum `000` | `#em` | Direct accept |
| 10 | Valid decimal checksum `117` | `?` | `023` accepted |
| 11 | Hex `75` for computed `117` | `?` | `000` accepted |
| 12 | Decimal last-two-digits `17` for computed `117` | `?` | `055` accepted |
| 13 | Valid decimal checksum `231` | `?` | `061` accepted |
| 14 | Hex `E7` for computed `231` | `?` | `040` accepted |
| 15 | Decimal last-two-digits `31` for computed `231` | `?` | `062` accepted |
| 16 | Decimal last-two-digits `00` for computed `100` | `?` | `093` accepted |
| 17 | Decimal last-two-digits `01` for computed `101` | `?` | `089` accepted |

What this proves:

- The emulator can keep IMPACT alive across many reject/recovery cycles and
  multiple analysis groups.
- Hex, single-character, and two-digit checksum representations are not accepted
  by this IMPACT copy for high-checksum rows.
- A low checksum by itself is not sufficient: `005` failed.
- `000`, `023`, `040`, `055`, `061`, `062`, `089`, `093`, and `099` have been
  accepted in at least one sweep context.

What this does not prove yet:

- It does not prove that changing only the textual representation of the same
  numeric result will work. The recovery rows use different numeric values.
- It does not yet isolate whether IMPACT rejects some rows because of checksum
  text, numeric field formatting, alloy plausibility/range checks, or a
  combination.

Next protocol test:

- Build `96 EMU FORMAT EQUIVALENCE SWEEP`: take rejected numeric rows and emit
  value-equivalent ASCII variants (`.059` vs `0.059`, extra trailing zeros,
  leading zeros, fixed width) until the checksum lands on an already-accepted
  value. If IMPACT accepts those variants, a receive-side canonicalization
  filter becomes viable without changing the chemical values.

## Next Test Profiles

### `96 EMU FORMAT EQUIV`

Profile: `impact-format-equivalence-sweep.json`.

Purpose: prove or disprove whether IMPACT can accept the same numeric results
when only the ASCII representation changes. This is the key safety gate before
building any receive-side canonicalization filter.

Coverage:

- Four known-rejected numeric rows: original checksum `100`, `101`, `117`, and
  `231`.
- For each base row, the original rejected row is sent as a control.
- Then value-equivalent variants are sent with checksums targeted to known
  accepted values: `000`, `023`, `055`, `089`, and `099` when a valid equivalent
  ASCII representation can be found.
- Variants use combinations that a C/DOS numeric parser should usually accept:
  leading zeros, trailing precision zeros, leading spaces, and explicit `+`
  signs.

Interpretation:

- If a variant is accepted, the checksum/content rejection can likely be worked
  around by rewriting only textual representation while preserving numeric
  values.
- If all variants are rejected, IMPACT likely rejects one of the numeric values,
  field widths, signs/spaces, or accumulated state rather than checksum alone.

First live result:

- Run folder: `C:\ARL\diagnostics\impact-emulator-20260709-081355`.
- The original checksum `100` control was rejected, as expected.
- Several value-equivalent checksum `100` variants were accepted with `#em`,
  including variants using explicit `+`, leading zeros, and extra precision.
- IMPACT later showed `Impact+ Error: Ratioed Intensities` on
  `format-equiv-101-to-000-leading-space-leading-zero-plus-precision`.
- The offending row began with `# 0042.97,...` and also included a field with a
  leading space before `+048.231`. This suggests that leading whitespace inside
  a numeric result field is unsafe even when the numeric value and checksum are
  valid.
- New safer profile: `98 EMU FORMAT SAFE`, backed by
  `impact-format-equivalence-safe-sweep.json`, keeps only format-equivalent rows
  that do not begin any numeric field with whitespace.

Follow-up after continuing past the dialog:

- User pressed through the `Ratioed Intensities` dialog and continued the same
  `96` session.
- IMPACT completed the remaining `96` cases. The only protocol rejections were
  the original control rows with checksums `100`, `101`, `117`, and `231`.
- Every format-equivalent row eventually received `#em`, including rows with
  leading spaces. Therefore the dialog is a higher-level IMPACT validation/UI
  error, not a serial/protocol rejection.
- Safer operational interpretation: plus signs, leading zeros, and extra
  precision are viable candidate transformations; leading whitespace inside
  result fields is risky and should not be used in a real filter.
- `98 EMU FORMAT SAFE` was revised to v2:
  - remove known-rejected original controls;
  - remove every row with a numeric field that begins with whitespace;
  - keep only eight accepted-style value-equivalent variants with valid
    checksums `000`, `023`, `055`, `089`, and `099`.

### `97 EMU CHECKSUM GRAMMAR`

Profile: `impact-checksum-grammar-sweep.json`.

Purpose: test row grammar around already-accepted low-checksum payloads.

Coverage:

- Leading `#` versus no leading `#`.
- Fixed three-digit checksum versus unpadded or four-digit checksum text.
- CR versus CRLF line ending.
- Delimiter experiments between payload and checksum.
- A known rejected checksum `100` control.

Interpretation:

- If no-hash rows are accepted, the leading `#` is optional for result rows.
- If unpadded or four-digit checksums are rejected, checksum width is fixed.
- If CRLF is accepted, line ending is tolerant; if rejected, keep CR-only.

## Implementation Notes

- The emulator profile must avoid using the same recovery row immediately after
  a control row. Two identical accepted rows can cause IMPACT to enter the
  `Store Result?` flow, which hides the checksum experiment.
- `95 EMU CHECKSUM SWEEP` now uses distinct values for every case and a sequence
  of distinct low-checksum recovery rows after `?`, so it can keep moving past a
  rejected case without triggering repeated-sample behavior.
- After run `impact-emulator-20260709-015659`, the profile was expanded from 9
  recovery rows to 40 and all checksum `005` recovery rows were removed because
  `005` was observed rejected both as a case and as a recovery.
- After `Store Result?` or cancel, IMPACT can send additional setup/new-sample
  commands such as `st ...`, `#st ...`, and `ns 0,0 173\r`; trace-derived
  profiles now include safe ACK fallbacks for those commands.
- A future real-ARL workaround, if emulator tests justify it, would be an
  optional receive-side filter in DOSBox-X-ARL that rewrites only result rows
  before IMPACT sees them. It must preserve numeric values and emit full audit
  records showing original row, transformed row, and both checksums.

## Open Questions

- Does IMPACT accept a high-checksum row if the checksum is presented as two
  digits?
- Does IMPACT accept leading-zero-shaped numeric rows with recomputed checksums
  below 100?
- Does the FreeDOS/native-COM path ever receive rows whose checksum is 100 or
  higher, and if so, does that IMPACT copy accept them?
- Are the HP and Dell using the exact same IMPACT binaries/configuration files?

## External Reference Notes

Public ARL 3460 manuals and brochures confirm the instrument family and
operation context, but the public documents found so far do not describe the
IMPACT+/ICS serial protocol or the `#rd/#em/?` checksum behavior.

General protocol references are still useful:

- ASCII sum modulo 256 is a common serial/instrument checksum family.
- Some protocols transmit modulo-256 checksums as fixed three-digit decimal
  text with leading zeros. The FIX checksum convention is one public example of
  a modulo-256 checksum rendered as `000-255` decimal text.
- Other ASCII serial protocols use two hex digits or LRC/two's-complement
  variants. Those are useful comparison points, but they do not match our
  observed ARL command/result rows as closely as decimal modulo 256.

Sources checked on 2026-07-09:

- Thermo Scientific ARL 3460 user/manual PDFs surfaced by Die Cast Machinery.
- Thermo Fisher ARL 3460 Advantage brochure.
- FIX Trading / FIX Dictionary references for ASCII byte-sum modulo 256
  checksums rendered as fixed-width three-character decimal text.
  - https://www.onixs.biz/fix-dictionary/4.2/app_b.html
  - https://www.b2bits.com/fixopaedia/fixdic44/tag_10_CheckSum.html
  - https://fiximate.fixtrading.org/legacy/en/FIX.4.2/tag10.html
- Public checksum references for ASCII sum modulo 256 and LRC-style ASCII
  protocols.
  - https://docklight.de/manual/checksum_specification.html
