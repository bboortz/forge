# Memory Index — forge

- [Design decisions](design-decisions.md) — Debian trixie + sid pinning, daily cron, two-stage FROM scratch runtime, grype+syft+cosign attestation triple, image set V1, beaconry integration constraint
- [Docker standard](docker-standard.md) — two-stage Dockerfile template, ldd discovery recipe, sid-pin file format, multi-arch build approach, what NOT to put in a Forge image
- [Supply chain](supply-chain.md) — grype scan step, syft SBOM, keyless cosign signing, downstream verify command, local developer flow
- [Code quality](code-quality.md) — commit format, branch naming, pre-PR checklist, shell / Dockerfile style
- [Workflow](workflow.md) — DD-TGD process (story → plan → red test → impl → CAPs → gates → audit), 9 canonical questions, gate matrix, capability matrix, new-image checklist
