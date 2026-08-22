#!/usr/bin/env python3
"""Assigns the permanent primary key for a catalogue exercise.

Every `CatalogExercise.id` is a UUID version 5 -- a hash, not a random value -- so that the same
movement gets the same id on every device and in every regeneration. That is what makes seeding
idempotent and convergent: two devices seeding the catalogue write identical rows instead of
duplicating each other. SQLiteData forbids a UNIQUE constraint on anything but the primary key for
a synchronized table, so there is no database-level backstop if this goes wrong.

    id = uuid5(uuid5(NAMESPACE_DNS, "catalog.hardset.app"), slug)

The first 50 entries were authored before this was written down and their ids do not follow it.
They are grandfathered and permanent -- changing one orphans every logged set that references it.
`CatalogIdSchemeTests` pins both halves of that: new entries must conform, and the exempt list
cannot grow silently.

Usage:
    python3 Tools/catalog_id.py hip-abduction-machine [more-slugs ...]
"""
import re
import sys
import uuid

NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "catalog.hardset.app")
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def catalog_id(slug: str) -> str:
    if not SLUG.match(slug):
        raise ValueError(
            f"{slug!r} is not a valid slug: lowercase alphanumerics separated by single hyphens. "
            "The slug is part of the key, so a typo here is permanent."
        )
    return str(uuid.uuid5(NAMESPACE, slug))


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        print(f"namespace = {NAMESPACE}")
        return 1
    for slug in argv[1:]:
        print(f'{catalog_id(slug)}  {slug}')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
