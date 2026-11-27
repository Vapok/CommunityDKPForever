# Changelog

All notable changes to CommunityDKP Forever are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Initial Release for World of Warcraft: Forever

This is the first release of CommunityDKP Forever, built for **World of Warcraft: Forever** (client `1.60.1`, Interface `16001`).

It works for small guilds running one 10-, 20- or 40-player raid, and for large guilds running several raid teams under the same guild tag.

### Highlights

- **Roster management for one team or many.** Run a single raid team, or set up several separate raid teams in the same guild, each with its own DKP table. Player specs and roles are picked up automatically, you can keep a standby bench, and DKP balances sync between officers and raiders.
- **A new dark-and-gold interface.** The main window has 7 tabs: Roster, Adjust DKP, Manage, Options, Loot History, DKP History, and Item Prices. The tabs sit along the side of the window, the Roster shows a class distribution bar graph, and both the Officer and Player bidding windows have been redone.
- **Raids, zones and world bosses for Forever.** Boss and zone support for the Forever launch raids: The Barrow Deeps (10-player), Hyjal Summit (20-player) and Onyxia's Lair (40-player), plus the world bosses: Azuregos, Lord Kazzak, Prince Thunderaan, and the four Dragons of Nightmare (Emeriss, Lethon, Ysondre and Taerar).
- **Several loot and bidding modes, including whisper bidding for PUGs.** Choose Minimum Bid Values, Static Item Values, Roll-Based Bidding, or Zero-Sum DKP. Guild members with the addon get a bidding window that pops up on its own. Players without the addon, including PUGs, can still take part by whispering `!bid`, `!dkp` and `!standby`.

### What's Included

#### New UI
- 7-tab main window with side tabs and a collapsible right-hand panel.
- Roster columns you can switch between class, spec, role, lifetime gained/spent and addon version.
- Class distribution graph under the filters.
- Officer Bidding window with min/max bid, bid timer, live bid list, Award Item and Disenchant buttons.
- Player Bidding window with quick +1 / +5 / Half / Max buttons, Cancel Bid and Pass.
- Options are also available from the game's **Options -> AddOns** menu (`/dkp settings`).

#### Raids and World Bosses
- The Barrow Deeps (8 bosses): Deepscar Matriarch, Elder Tangleclaw, Khalith the Dreadspinner, Well of Sorrow, Amethrax, Del'lynar Songwood, Ravus and Darlissa, Sonya Darkhallow.
- Hyjal Summit (13 bosses): Bandalar, Ancient of Decay, Time-Lost Battalion, Sylvestris Dusksong, Old Gloomlurker, Gharalis the Abyssal, Kathris the Haunted, Anara Chillwind, Elder Minderel, Tracker Stillwind, Council of Thorns, Nythus the Dreambound, The Wild King.
- Onyxia's Lair: Onyxia.
- World Bosses (7): Azuregos, Lord Kazzak, Emeriss, Lethon, Ysondre, Taerar, Prince Thunderaan.
- Optional automatic DKP awards on boss kills.

#### Multiple Teams and Syncing
- Create and rename raid teams (Guild Leader only).
- When an officer starts the Raid Timer, everyone in the raid switches to that raid's team.
- On login, a player who belongs to only one team is put on that team automatically.
- Officer whitelist to control who can edit and broadcast DKP.
- "Merge Last 2 Weeks" and "Full Broadcast" options to get everyone caught up.

#### Bidding and Loot
- Minimum Bid, Static Item Values, Roll-Based and Zero-Sum modes.
- Default minimum and maximum bid values per gear slot.
- Whisper commands for players without the addon: `!bid`, `!bid cancel`, `!dkp`, `!standby`.
- Loot History and DKP History with search, plus right-click edit and delete for officers.
- Item Prices list showing each item's price and disenchant count.

#### Combat-Safe Syncing
- Addon messages that would be blocked during a boss encounter are held and sent once the fight ends, so boss kill awards and raid timer ticks aren't lost.
- Bidding is paused during an active boss encounter and can be run once combat ends.

---

CommunityDKP Forever continues CommunityDKP, which was itself forked from [MonolithDKP](https://www.curseforge.com/wow/addons/monolith-dkp). It has been rebuilt for World of Warcraft: Forever.
