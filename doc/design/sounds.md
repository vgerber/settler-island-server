# Sounds and music: open sources

Researched 2026-11-27. Only CC0 sources, so the files can live in the public repository with no attribution duties
(a credits line is still polite). Confirm the licence on each page when downloading; OpenGameArt pages can change.
Files go to `client/godot/audio/<hook>.ogg` (the `Sfx` autoload from `feedback.md` looks them up by hook name), with
the pack's licence file next to them under `client/godot/audio/licenses/`.

## Sources
| Pack | Licence | Files | Use for |
|---|---|---|---|
| [Kenney Casino Audio](https://kenney.nl/assets/casino-audio) | CC0 | about 50: cards, dice, chips | dice shake/land, all card movement, trades, development cards |
| [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) | CC0 | 130 impacts (wood, plank, generic) | placing settlements, roads, cities, the robber |
| [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) | CC0 | 100 clicks, toggles, confirmations | buttons, hover, errors, turn start, trade answers |
| [Kenney RPG Audio](https://kenney.nl/assets/rpg-audio) | CC0 | 50 foley (coins, cloth, metal) | paying and gaining, awards, victory |
| [2 dice roll (29 throws), OpenGameArt](https://lpc.opengameart.org/content/2-dice-roll-29-throws) | CC0 | 29 two-dice throws | alternative dice roll with two dice (matches our two dice) |
| [Kenney Boardgame Pack](https://opengameart.org/content/boardgame-pack) | CC0 | board game art plus bonus sounds | spare pool if a hook needs more variety |

Music (optional, off or quiet by default, one looping track in the lobby and one at the table):
| Track | Licence | Note |
|---|---|---|
| [Medieval: The Old Tower Inn](https://opengameart.org/content/medieval-the-old-tower-inn) | CC0 | full and loop versions; tavern feel |
| [Medieval: King's Feast](https://opengameart.org/content/medieval-kings-feast) | CC0 | loop version |
| [Medieval: Minstrel Dance](https://opengameart.org/content/medieval-minstrel-dance) | CC0 | upbeat, loop version |
| [Crowded Pub](https://opengameart.org/content/crowded-pub) | CC0 | short loop, 2025 remix with more parts |

Atmosphere (an `Ambience` bus with its own slider, quiet by default; island bed at the table, calm music in menus):
| Source | Licence | Use |
|---|---|---|
| [Beach Ocean Waves](https://opengameart.org/content/beach-ocean-waves) | CC0 | 4 wave files: the surf bed under the table, crossfaded into a loop |
| [Sea and river wave sounds](https://opengameart.org/content/sea-and-river-wave-sounds) | CC0 | tagged loop, 5 min cut; softer water layer |
| [Solo seagull sound effects](https://opengameart.org/content/solo-seagull-sound-effects) | CC0 | single gull calls, played at random every 20-60 s over the waves |
| [Sea waves and terns (Big Sound Bank)](https://bigsoundbank.com/sea-waves-and-seagulls-s0267.html) | CC0 | ready-made shore recording, alternative bed |
| [Snow theme](https://opengameart.org/content/snow-theme) | CC0 | 24 s seamless calm loop for the lobby browser |
| [Town theme RPG](https://opengameart.org/comment/104122) | CC0 | harps and recorders; lobby room or calm table music |
| [Peaceful Town](https://opengameart.org/node/131208) | CC0 | calm village track, check length before use |
| [CC0 Calm / Relaxing Music](https://opengameart.org/node/73274) | CC0 | collection to pick further calm tracks from |

Not usable here (attribution or share-alike): Gull Sounds (CC-BY-SA), Snowy Village, Relaxed Village and Peaceful
village loop (CC-BY).

Avoid for the repository: CC BY sounds (need credits we would have to track), "free with attribution" generator
sites, and royalty-free commercial packs (licences forbid redistributing the raw files in a public repository).

## Hook mapping (from `feedback.md`)
| Hooks | Source |
|---|---|
| `sfx_dice_shake`, `sfx_dice_land`, `sfx_roll_seven` (lower-pitched land or a second throw layered) | Casino Audio dice, or the 2-dice-roll throws |
| `sfx_place_settlement`, `sfx_build_city`, `sfx_robber_move` | Impact Sounds wood/plank (heavier impact for a city) |
| `sfx_place_road` | Impact Sounds light wood tap |
| `sfx_card_gain`, `sfx_pay`, `sfx_discard`, `sfx_steal`, `sfx_stolen_from_me`, `sfx_dev_buy`, `sfx_dev_gain`, `sfx_monopoly` | Casino Audio card slides, places and shuffles (vary pitch per hook) |
| `sfx_trade_bank`, `sfx_trade_done` | Casino Audio chips |
| `sfx_trade_offer`, `sfx_trade_accept`, `sfx_trade_reject`, `sfx_trade_cancel` | Interface Sounds confirmation / back / close |
| `sfx_dev_play_*` | Casino Audio card flip, plus Impact for the knight |
| `sfx_award_road`, `sfx_award_army`, `sfx_victory`, `sfx_game_over` | RPG Audio coins/metal, Interface confirmation |
| `sfx_turn_start`, `sfx_attention`, `sfx_error`, `sfx_ui_click`, `sfx_ui_hover` | Interface Sounds |

Volume: `Sfx`, `Music` and `Ambience` buses with separate sliders in the settings autoload; music starts muted until
the player turns it on.
