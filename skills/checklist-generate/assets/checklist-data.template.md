# Data Checklist

Generated from the `data/input/` and `data/output/` context documents. Do not hand-edit to close a gap — fix the source context doc and regenerate instead.

## Input: <dataset name> (source: data/input/<doc>)

- [ ] Schema field `<name>` (`<type>`, nullable: <y/n>) validated against real data
- [ ] Validation rule: <rule stated in the doc> enforced on arrival
- [ ] Sensitivity: `<PII/PHI/financial field>` masked/classified per doc
- [ ] Documented sample (10–20 rows) matches the real source

## Output: <dataset name> (source: data/output/<doc>)

- [ ] Schema field `<name>` (`<type>`, nullable: <y/n>) implemented
- [ ] Derivation: `<output field>` = <rule> from `<input field(s) or constant>` (traced to data/input/<doc>)
- [ ] Quality guarantee / reconciliation check: <check stated in the doc>
- [ ] Versioning/compatibility rule: <rule stated in the doc>

## Gaps

- [ ] ⚠ gap — <output field with no traceable input field or constant>
- [ ] ⚠ gap — <dataset with missing schema / validation rules / sensitivity classification>
