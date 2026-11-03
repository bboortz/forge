# The 9 canonical clarification questions

Every Forge story (`docs/stories/FG-NNN-<slug>.md`) answers these nine questions before moving from `draft` to `ready`.

1. **Who** is the consumer in this moment? (Python dev / security engineer / ops / auditor / Forge maintainer)
2. **When** does the story fire? (trigger — new CVE in sid, consumer verifies image, maintainer adds image, auditor runs compliance report, scheduled cron)
3. **What** does success look like? (observable: grype output, cosign verify exit code, specific tag resolves, image size)
4. **How urgent?** (impact tier — security-critical / correctness / quality-of-life / foundation)
5. **Happy path** — exact sequence of consumer or pipeline steps?
6. **Edge cases / failure modes** that matter?
7. **Out of scope** — what could creep in but shouldn't?
8. **How do we know it's done?** (acceptance test wording = Gherkin)
9. **What capabilities does this story deliver or extend?** Name new CAP ids; link to existing ones in `docs/CAPABILITIES.md`.

Rules:

- Every question gets an answer. "N/A" is a valid answer but must be explicit.
- Question 9 lists at least one CAP for every `ready+` story. `make verify-traceability` enforces this.
- Rephrasing is fine; renumbering is not — downstream tooling and audits reference these by number.
