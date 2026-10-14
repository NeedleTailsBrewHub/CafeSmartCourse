# Sample café data

Neighborhood specialty-café fixtures for CMS import, recipe planning, and offline ML demos.

| File | Purpose |
|------|---------|
| `menu.csv` | **Import-ready** — matches `POST /api/auth/menu/import` (`id,name,priceCents,…,imageMediaKey`) |
| `inventory.csv` | **Import-ready** — matches `POST /api/auth/inventory/import` (kitchen units: `g` / `l` / `ml` / `ea`) |
| `recipes.csv` | Recipe BOM — `unitsPerItem` is in the inventory SKU’s stock unit (e.g. `18` g beans, `0.25` L milk) |
| `menu_catalog.csv` | Human-readable menu + allergen + image path reference (not the API import schema) |
| `inventory_catalog.csv` | Planning fields (par, lead time, cost, storage) beyond the slim import CSV |
| `*_training.csv` | Offline trainer demos; regenerate with `scripts/regenerate_training_csvs.py` |
| `menu-images/` | Local product photos served under `/menu-images/…` in DEBUG |

Runtime Mongo seed (`DemoCafeSeed`) uses a smaller overlapping catalog with the same SKU/unit conventions (`BEANS-ESP-1KG` in **g**, milk in **l**, pastries in **ea**).
