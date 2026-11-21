# Contributing

- **Everything builds from source.** No binaries, blobs, BIOS, ROMs, or stock-derived files in the repo or
  the image.
- **No stock material.** Do not copy vendor firmware, vendor binaries, or the stock device-lock. Analysis of
  stock firmware stays out of this repo.
- **Provenance.** Pin every upstream (tag + hash) and add it to [`PROVENANCE.md`](PROVENANCE.md) with its
  licence.
- **Evidence tags.** Every claim states whether it was checked on hardware (`[V]`) or is desk-only.
- **Security defaults are not optional.** Per-unit credentials, firewall-on, least privilege — don't regress
  them (see [`SECURITY.md`](SECURITY.md) / [`docs/risks-eliminated.md`](docs/risks-eliminated.md)).
- **One topic per branch → PR into `main`.** CI (docs + build + smoke + hardening + licence) must pass.
  `main` is protected.
- Device safety: never drive an unidentified panel; never undervolt below stock; never change the thermal
  critical trip.
