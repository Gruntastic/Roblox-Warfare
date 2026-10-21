# Assets (ForgeGUI)

All art below was made with ForgeGUI and published to Roblox as Image assets under the owner's account
(creator user 2930909850). The ids live in `src/shared/Config/Assets.luau`; a slot set to `0` makes the
UI fall back to its code-drawn look, so any slot can be replaced or left empty without breaking anything.

Scope agreed with the owner: images only (about 36,800 credits). No 3D models, animations or sounds were
generated; ask before any further paid generation.

## How each kind is used

- **Emblem**: top bar crest. **Wordmark / WordmarkAlt** are published but unused: the art is AI-drawn
  text, so the top bar renders "BLOX OPS" as text until someone checks the spelling in Studio.
- **ButtonPlate / PanelFrame**: published 9-slice candidates, not wired yet (slice margins need
  measuring in Studio).
- **Icon.\***: lobby side nav, QUEUE/SHOP buttons, squad invite and credit counter.
- **Mode.\***: mode select cards (PlayMenu). **Map.\***: map vote cards. **Crate.\***: loot crate art.
- **StagingBackdrop**: back wall of the staging hangar.
- **Team/gear clothing** (classic 585x559 Shirt/Pants templates): a gear set's pair is used only when
  both pieces exist; otherwise the team piece is used, and plain colour where that is missing too.
  Today that means Sable wears its shirt and pants, Talon wears its pants with a coloured torso, and
  NightOps pants are published but unused until a NightOps shirt exists.

## Not made

Five jobs ended "outcome unknown" on ForgeGUI's side. They were not regenerated (ForgeGUI's rule:
never regenerate an outcome_unknown job, since it may still have charged). Their slots stay `0`:
`Icon.Gunsmith`, `Talon.Shirt`, `Arctic.Shirt`, `Arctic.Pants`, `NightOps.Shirt`.

## Animations and gear

ForgeGUI's R15 animation routes were not available, so operator animations are procedural
(`Controllers/OperatorAnimator.luau`, Motor6D transforms) and gear is built from parts
(`GearBuilder.luau`). `Assets.GearModels` is a placeholder for future mesh gear and nothing reads it.

## Registry

| Slot | ForgeGUI job | Publication | Roblox asset id |
|---|---|---|---|
| `Emblem` | (earlier batch) | b7f6da22-fc83-4929-8b20-ddeb08140166 | 118115512723395 |
| `Mode.TDM` | (earlier batch) | 339e2812-2833-4635-9122-e5680fc28908 | 138888433675654 |
| `Wordmark` | (earlier batch) | b3805e73-e702-4f0b-8163-aa1453b75cc1 | 70671837095623 |
| `WordmarkAlt` | (earlier batch) | 08cfd011-1492-4234-ac7e-18711827481f | 128654814891850 |
| `ButtonPlate` | (earlier batch) | c03e1b0b-1074-4693-9ce8-481a97f54f4c | 123335665778673 |
| `PanelFrame` | (earlier batch) | 1b64dc97-2042-4d63-8b8c-04002fe47176 | 136481523974556 |
| `Icon.Invite` | 086b8aaf-f192-4dc5-9423-5a4d321f5bbf | fb37e1e4-486b-4ac8-a463-70c49920c70f | 119113864005333 |
| `Icon.Shop` | 24c83185-670b-41e8-b9e6-9389c804b077 | 6425679f-8f44-4b11-b9e9-32751af0165b | 82267407289363 |
| `Icon.Queue` | 6c1f2e0d-3b70-4ec2-8aac-19314f2b6940 | fd278c5a-9744-4301-98bc-38a7b67a4d46 | 75984596555566 |
| `Icon.Operator` | 177d3e59-085b-4642-8c52-aab08d767b2a | 15bbf63b-38a6-4dbb-98be-71ec02e251f7 | 102981023062353 |
| `Icon.Barracks` | e5c0072c-d9d3-4687-bd36-f0211d8184a0 | ff160b7e-70d8-4ef5-a513-a62c827bb665 | 71773357024240 |
| `Icon.Perks` | 31b3e914-9293-4458-93c6-fc2442c40a9e | 8c87ef91-4e89-45e6-9756-a8beb051dd41 | 98292108000414 |
| `Icon.Streaks` | 426bf596-0c77-4783-ae5f-9d8f55620b10 | a9c2efd0-4146-4b72-8ee2-f47ee52d7b27 | 135539716720049 |
| `Icon.Credits` | ad0604df-bee3-47e3-9c49-e3900e361bfd | 5df33a63-7baf-47e9-a8b6-803341279ab8 | 90338914172903 |
| `Icon.Loadout` | 3bc6b723-6a81-481f-9605-b176a04568f8 | 24134537-8d0f-4603-9bf8-f3c03e12243f | 128230900418279 |
| `Mode.FFA` | a39824f4-2777-4b27-a2e1-73ce346edc50 | f0988a05-fe1d-4d60-b56d-2cb4e0c30ef1 | 137768731021610 |
| `Mode.DOM` | e9385a1b-5a31-4f4d-9775-6cd8fe1ab524 | 82cf7bdc-7c4c-4243-ab9c-401f184dbf69 | 93084643899574 |
| `Mode.SND` | 5b0ba90d-38ed-4a95-bf5f-efb7815a1d83 | 6d0a212d-8ab7-43dd-b794-91b203324aa5 | 88033669720864 |
| `Mode.HP` | 957248f5-84e9-4828-bdad-506a0eddc3c2 | 3c246701-cc2e-46ec-810a-87119531ebd6 | 122104109212964 |
| `Mode.KC` | 664a0b2d-65c7-48f3-9e0b-137814b6ba02 | 1c4a4065-90cc-497c-9eaf-51461247dc56 | 122982218119264 |
| `Mode.Any` | f32ab063-ec8b-4b57-be98-ece7da03cacf | 8ebdab7d-b25c-4656-86f2-92ddc38c13d0 | 120164935087933 |
| `Map.DustlineTerminal` | d2e73000-2ffe-4adb-a297-bfe44b4b54e8 | 68e711a3-727f-4870-b454-c15ebef83883 | 71148569132712 |
| `Map.AshwoodEstate` | fc31fd7e-a41c-45f0-8b3c-f4ba5ccabb8c | ad5499c0-f53c-4a08-bb23-3aafde2fc0a8 | 106950438266405 |
| `Map.Breakwater` | 51a62e71-5b30-4097-b039-478c180b1138 | 1f51537c-6c05-4f9a-85f6-b39672478f1e | 139382392145510 |
| `Map.FrostRelay` | 6762a81b-852f-4c90-80f0-df13f8a20026 | 634090bd-3276-49a2-a0bb-175b2e3a62ac | 81657916482451 |
| `Map.IronBorough` | 88f0439a-345b-4118-a4c7-2d90c0008747 | ed31b524-6365-493d-980c-bf21f6b59fb3 | 97584074198696 |
| `Map.RedMesa` | 8c20a66b-e370-4395-a673-571fee054e0f | ddaf7355-57c1-412a-a307-26b0e8c1dd66 | 73695390093233 |
| `Crate.Supply` | ca2ca73b-354f-4318-945c-a4e1ecdf88b4 | 04dbc749-3c62-4941-859d-678a6b985465 | 89203956507124 |
| `Crate.Gear` | fc81a9ab-824f-4323-b076-589fc16bfc42 | 0ffdedfd-8a01-4865-8f72-31fd658b5621 | 135572800292611 |
| `StagingBackdrop` | 0a634a3e-9fed-4bb2-98de-f8da7eee50b5 | 412b1426-3b44-4d2d-bc6f-b057e5eebf5c | 131024147372939 |
| `Sable.Shirt` | b4c0cead-95e8-499d-a690-4e89b8261211 | d34898d6-f51c-49d3-8f8b-7b068792edbe | 107310306442215 |
| `Sable.Pants` | 1cd23e66-8abc-4322-bf8b-b55435e6b0c2 | a862461f-70e9-4662-8ada-7c784b22240a | 108995154010417 |
| `Talon.Pants` | f5ded083-8864-4102-9e16-cd40a9222e87 | 1e61da44-d3c2-474f-9c03-a90a2520189a | 85793974904905 |
| `NightOps.Pants` | e93bf2bf-bfa9-4030-b5f7-ee0de43a9325 | 519c6ea4-35a8-4a0c-a9a3-d09ad34894ea | 98347295472879 |
| `Icon.Gunsmith` | ab93ff67-134e-4be1-bb52-3a077bc97dc9 | - | not made (outcome unknown) |
| `Talon.Shirt` | 68a24b11-3576-4ec1-8c77-87ba5be5d630 | - | not made (outcome unknown) |
| `Arctic.Shirt` | 1a2fef57-49d8-44a0-9592-b58912af61f6 | - | not made (outcome unknown) |
| `Arctic.Pants` | b0024635-8de0-4428-9ecb-07379c7cb929 | - | not made (outcome unknown) |
| `NightOps.Shirt` | 9d0ebafb-5465-409d-b29b-15000c5f1e79 | - | not made (outcome unknown) |
