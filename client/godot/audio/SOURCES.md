# Audio sources

All files are CC0 (licence confirmed on each source page on 2026-11-27, texts in `licenses/`). Every file was
converted to Ogg Vorbis (mono, 44.1 kHz for effects), trimmed of leading silence and peak-normalised to -3 dB; the
build recipe is in the commit history of this file. `down x` means played slower by factor x (lower pitch).

Kenney packs came from OpenGameArt because kenney.nl blocks scripted downloads, so the Casino Audio, Impact
Sounds and RPG Audio packs from `doc/design/sounds.md` are not used.
The OpenGameArt "2 dice roll (29 throws)" pack is a .7z archive and was skipped.

Packs (author, URL):
- Boardgame Pack v2 (Kenney): https://opengameart.org/content/boardgame-pack, `boardgamePack_v2.zip`, `Bonus/`
- Interface Sounds 1.0 (Kenney): https://opengameart.org/content/interface-sounds, `kenney_interfaceSounds.zip`
- RPG Sound Pack (artisticdude): https://opengameart.org/content/rpg-sound-pack, `rpg_sound_pack.zip`
- Beach Ocean Waves (qubodup, recordings by jasinski): https://opengameart.org/content/beach-ocean-waves
- Solo Seagull Sound Effects (Rango Mango): https://opengameart.org/content/solo-seagull-sound-effects
- Snow Theme (CleytonKauffman): https://opengameart.org/content/snow-theme
- Medieval: The Old Tower Inn (RandomMind): https://opengameart.org/content/medieval-the-old-tower-inn

## Effects (Boardgame = Bonus/ of the Boardgame Pack, Interface = Audio/, RPG = RPG Sound Pack/)
| Repo file | Original file | Edit |
|---|---|---|
| sfx_dice_shake | Boardgame dieShuffle1.ogg | |
| sfx_dice_land | Boardgame dieThrow1.ogg | |
| sfx_roll_seven | Boardgame dieThrow2.ogg | down 0.8 |
| sfx_place_settlement | RPG inventory/wood-small.wav | |
| sfx_place_road | RPG inventory/wood-small.wav | up 1.25 |
| sfx_build_city | RPG world/door.wav | first 0.6 s, fade out |
| sfx_robber_move | RPG world/door.wav | down 0.7, first 0.7 s |
| sfx_card_gain | Boardgame cardSlide1.ogg | |
| sfx_pay | Boardgame cardPlace1.ogg | |
| sfx_discard | Boardgame cardSlide3.ogg | |
| sfx_steal | Boardgame cardSlide2.ogg | up 1.15 |
| sfx_stolen_from_me | Boardgame cardPlace3.ogg | down 0.8 |
| sfx_trade_bank | Boardgame chipsCollide1.ogg | |
| sfx_trade_offer | Interface question_001.ogg | |
| sfx_trade_accept | Interface confirmation_001.ogg | |
| sfx_trade_reject | Interface back_002.ogg | |
| sfx_trade_done | Boardgame chipsCollide2.ogg + RPG inventory/coin3.wav | joined |
| sfx_trade_cancel | Interface close_001.ogg | |
| sfx_dev_buy | Boardgame cardPlace2.ogg | |
| sfx_dev_play_knight | RPG battle/swing2.wav | |
| sfx_dev_play_road_building | RPG inventory/wood-small.wav twice | up 1.2 |
| sfx_dev_play_year_of_plenty | RPG inventory/coin.wav | |
| sfx_dev_play_monopoly | Boardgame cardSlide2.ogg + cardPlace1.ogg | joined, down 0.9 |
| sfx_dev_play_victory_point | Interface confirmation_002.ogg | |
| sfx_monopoly | Boardgame cardSlide1.ogg + cardSlide3.ogg | joined, down 0.85 |
| sfx_dev_gain | Boardgame cardSlide1.ogg | up 1.15 |
| sfx_award_road | RPG inventory/coin2.wav | |
| sfx_award_army | RPG inventory/metal-ringing.wav | |
| sfx_turn_start | Interface bong_001.ogg | |
| sfx_attention | Interface glass_001.ogg | |
| sfx_error | Interface error_003.ogg | |
| sfx_victory | Interface confirmation_004.ogg + RPG inventory/metal-ringing.wav | joined |
| sfx_game_over | Interface confirmation_003.ogg | down 0.8 |
| sfx_ui_click | Interface click_002.ogg | |
| sfx_ui_hover | Interface tick_001.ogg | |

## Ambience and music
| Repo file | Original file | Edit |
|---|---|---|
| ambience/waves_loop | Beach Ocean Waves wave_01..04_cc0-18363__jasinski__alkaibeach.flac | joined with 0.4 s crossfades, tail mixed into the head for a seamless loop |
| ambience/gull_1..4 | Solo Seagull `Seagull Ambient 1..4.wav` | mono, loudness-normalised |
| ambience/gull_5 | Solo Seagull `Seagull Big Ambient.wav` | mono, loudness-normalised |
| music/menu_snow_theme | Snow Theme `bgm_snow_theme_loop.ogg` | re-encoded |
| music/table_old_tower_inn | Old Tower Inn `Loop_The_Old_Tower_Inn.wav` | re-encoded |
