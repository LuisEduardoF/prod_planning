---
name: context-scaffold
description: Create the project `context/` folder — business/, product/, data/input/, data/output/ and a README.md documenting the expected PDF format for each. Use when the user asks to set up, scaffold, initialise, or repair the context folder, or asks where project context PDFs should go.
---

# Context folder scaffold

Creates (or repairs) the `context/` documentation tree at the repo root. Everything in it is PDF context files; the README explains what each PDF must contain.

## Target structure

```
context/
├── README.md
├── business/
│   └── .gitkeep
├── product/
│   └── .gitkeep
└── data/
    ├── input/
    │   └── .gitkeep
    └── output/
        └── .gitkeep
```

## Steps

1. **Locate the root.** Default to the primary working directory unless the user names another path.

2. **Inspect before writing.** Run `find context -maxdepth 3 2>/dev/null` (or list the target path). This skill is idempotent — it fills gaps, it never overwrites existing content.

3. **Create missing directories only:**
   ```bash
   mkdir -p context/business context/product context/data/input context/data/output
   ```

4. **Add `.gitkeep`** to each of the four leaf directories that is currently empty, so the structure survives version control. Skip any directory that already has files.

5. **Write `context/README.md`** from `assets/README.template.md` in this skill directory — copy it verbatim.
   - If `context/README.md` **does not exist**: copy the template in.
   - If it **already exists**: do not overwrite. Read it, tell the user it is already there, and offer to merge in any missing sections from the template.

6. **Report** the resulting tree and say plainly which items were created versus already present.

## Notes

- Never delete or move anything already inside `context/`.
- Do not invent placeholder PDFs — the README describes what belongs there; filling it is the user's job.
- If the user wants extra top-level domains beyond business/product/data, add them as siblings and append a matching section to `context/README.md` following the same shape as the existing sections.
