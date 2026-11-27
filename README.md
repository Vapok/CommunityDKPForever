# CommunityDKP Forever

CommunityDKP Forever is an in-game DKP addon for **World of Warcraft: Forever**. It covers everything a raiding guild needs: tracking DKP, running loot bids, keeping a record of who got what, and handling raid attendance.

It works whether your guild runs one raid group or several. You can keep separate DKP tables for multiple raid teams in the same guild, keep a standby bench, and let players who don't have the addon (like PUGs) bid through whispers. Officers' changes sync out to everyone else in the guild who has the addon.

- **Game client:** World of Warcraft: Forever `1.60.1` (Interface `16001`)
- **Install folder:** `World of Warcraft/_forever_/Interface/AddOns/CommunityDKPForever`
- **Changes:** see [CHANGELOG.md](CHANGELOG.md)

![Roster window](Media/Roster%20Window.png)

---

## Contents

- [Features at a Glance](#features-at-a-glance)
- [Setting Up Your Guild and Roster](#setting-up-your-guild-and-roster)
- [Running a Raid](#running-a-raid)
- [Handing Out Loot and Running Bids](#handing-out-loot-and-running-bids)
- [How PUGs (or Anyone Without the Addon) Can Bid](#how-pugs-or-anyone-without-the-addon-can-bid)
- [How the Standby List Works](#how-the-standby-list-works)
- [Officer Checklist](#officer-checklist)
- [Slash Commands](#slash-commands)
- [Tips and Backups](#tips-and-backups)

---

## Features at a Glance

### Four DKP modes

Pick one in `/dkp modes`:

| Mode | How it works |
|---|---|
| **Minimum Bid Values** | Each item has a minimum bid. Players bid DKP and the officer picks the winner (usually the highest bid). The bid can be fixed or run like an auction. |
| **Static Item Values** | Every item has a set price. Players say they want it and the officer picks who gets it. |
| **Roll-Based Bidding** | Players `/random` within a range based on their DKP. Highest roll wins. |
| **Zero-Sum DKP** | DKP spent on an item is split back out to the rest of the raid, so the total DKP in the guild stays the same. |

### The main window (`/dkp`)

The DKP roster is always on the left. The tabs down the right-hand side change what shows in the right panel.

| Tab | What it's for |
|---|---|
| **Roster** | Search the DKP table and filter it by class, by who's in your group, who's online, or who isn't in the raid. The column dropdown switches between class, spec, role, lifetime DKP gained/spent and addon version. A class distribution graph sits underneath. |
| **Adjust DKP** | Give out boss kill bonuses, run the Raid Timer (on-time bonus plus ticks every so many minutes), make manual adjustments, apply weekly percentage decay, or hand out Zero-Sum DKP. |
| **Manage** | Add guild or raid members to the DKP table, remove players, set up raid teams, and set the officer whitelist. |
| **Options** | Default bonus amounts, minimum and maximum bids per gear slot, bid timer length, window scale and tooltip settings. |
| **Loot History** | Every item handed out: who got it, what it cost, and which boss and zone it came from. Officers can right-click an entry to edit/reassign it or delete it. |
| **DKP History** | Every DKP award, adjustment and decay. Officers can right-click an entry to delete it, which refunds or removes the DKP it gave out. |
| **Item Prices** | A list of item prices (minimum bid or fixed cost) and how many times each item has been disenchanted. |

| Adjust DKP | Manage |
|---|---|
| ![Adjust DKP tab](Media/Adjust%20DKP%20Window.png) | ![Manage tab](Media/Manage%20Roster%20Window.png) |

| Options | Item Prices |
|---|---|
| ![Options tab](Media/DKP%20Options.png) | ![Item Prices tab](Media/Price%20Listing.png) |

| Loot History | DKP History |
|---|---|
| ![Loot History tab](Media/Loot%20History%20Window.png) | ![DKP History tab](Media/DKP%20History.png) |

---

## Setting Up Your Guild and Roster

### 1. First-time setup (Guild Master)

1. Type `/dkp modes` and choose your DKP mode on the **Modes** tab.
2. Open `/dkp` and go to the **Options** tab. Fill in:
   - **Default DKP Award Values**: On Time Bonus, Boss Kill Bonus, New Boss Kill Bonus, Raid Completion Bonus, Unexcused Absence, and Decay Amount.
   - **Default Minimum Bid Values** (and maximum bid values, if you use them) for each gear slot.
3. Click **Save Settings**.
4. Go back to `/dkp modes` and click **Broadcast Settings** so every officer has the same setup.

### 2. Adding players to the DKP table

Go to the **Manage** tab and use one of these:

- **Add Guild Members**: pick a guild rank from **Select Rank**, then click **Add Guild Members** to add everyone at that rank.
- **Add Raid Members**: adds everyone in your current raid or party who isn't on the table yet.
- **Add Target**: adds the player you have targeted. This also works for people outside your guild.

To take players off the table, select them in the roster and click **Remove Entries**.

### 3. Running more than one raid team

If your guild has more than one raid group, each team can have its own DKP table.

- On the **Manage** tab, under **Teams**, the Guild Master can click **Add new team**, or pick an existing team and click **Rename team**.
- The **Team:** dropdown at the bottom of the main window switches which team's table you're looking at.
- When a player logs in and is only on one team's roster, the addon switches them to that team on its own. If they're on more than one team (or none), it leaves their selection alone.
- When an officer starts the Raid Timer, everyone in the raid is moved to that raid's team.

### 4. Officer whitelist (optional)

By default, every guild officer can edit and broadcast DKP. If you only want certain officers to have that access, the Guild Master can use **Whitelist Settings** on the **Manage** tab:

1. Select the officers you want in the roster (Shift+Click to select more than one).
2. Click **Set Whitelist**, then **Send Whitelist** to share it with the guild.
3. Use **View Whitelist** to check who's on it.

Send the whitelist when all your officers are online, so everyone gets it. To clear the whitelist, click **Set Whitelist** with nobody selected. If you're happy with all officers having access, you can skip the whitelist.

---

## Running a Raid

### Starting the raid

1. Make sure the **Team:** dropdown at the bottom of `/dkp` is set to the team that's raiding tonight.
2. If anyone new is in the raid, go to **Manage** and click **Add Raid Members**.
3. Go to the **Adjust DKP** tab and look at the **Raid Timer** box:
   - **Interval**: how many minutes between DKP ticks.
   - **Bonus**: how much DKP each tick gives.
   - Tick **Give On Time Bonus** to award the on-time bonus right away, **Give End Bonus** to award the raid completion bonus when you stop, and **Include Standby** to give the same DKP to your standby list.
4. Click **Initialize Raid**. Everyone in the raid will switch to this team, and DKP ticks will go out on the interval you set.

Need a break? Click **Pause Raid**, then **Continue Raid** when you're ready again. When the raid is over, click **End Raid**.

Any officer in the raid can start the timer, but only the raid leader's addon actually gives out the DKP. If the raid leader disconnects, pass raid lead to another officer who still has the timer running.

### Automatic boss kill awards

To have DKP handed out on boss kills without anyone clicking anything:

1. Open `/dkp modes` and go to the **Options** tab.
2. Tick **Auto Award DKP**. Tick **Include Standby** in the same section if your bench should get it too.

Once the raid has been started with **Initialize Raid**, killing a boss in Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, AQ20, AQ40, Naxxramas, or one of the world bosses (Azuregos, Lord Kazzak, Emeriss, Lethon, Taerar, Ysondre) gives out the Boss Kill Bonus from your Options tab. Only the raid leader's addon gives out the award, so it won't be paid twice.

If a boss fight is going on, the addon holds its sync messages and sends them when the fight is over. Nothing gets lost.

---

## Handing Out Loot and Running Bids

### Opening a bid (officers)

Either:

- Hover your mouse over the item (in the loot window or your bags) and press **Shift + Alt**, or
- Type `/dkp bid` followed by the item link (Shift+Click the item into the chat box), for example `/dkp bid [Onslaught Girdle]`.

Hovering an item and pressing **Shift + Ctrl** skips the bid and opens the award window for that item directly.

> Bidding can't be started, submitted or awarded during an active boss encounter. Wait until the fight is over.

### The Officer Bidding window

![Officer Bidding window](Media/Officer%20Bidding%20Window%20(with%20Bids).png)

1. Check the item and the **Boss** it came from (change it from the dropdown if needed).
2. Check the **Minimum Bid** and **Maximum Bid**. These come from your Options tab defaults. Tick **Custom** and type a new number to set a different price for this item. The custom price is saved for next time.
3. Set the **Bid Timer** in seconds and click **Start Bidding**. A countdown bar shows up for the raid.
4. As bids come in, they appear in the **Bids** list with each player's bid (or roll) and total DKP.
5. Click the winner in the list, check the **Item Cost**, and click **Award Item**.
6. If nobody wants it, click **DE** to log it as disenchanted.

Click **Clear Window** to reset the window for the next item.

### The Player Bidding window (raiders with the addon)

![Player Bidding window](Media/Player%20Bidding%20Window.png)

When an officer starts a bid, this window opens on its own (untick **Auto Open Bid Window** if you'd rather open it yourself with `/dkp bid`).

- Type your bid, or use **+1**, **+5**, **HALF** and **MAX** to fill it in.
- Click **Submit Bid** to bid, **Cancel Bid** to take it back, or **Pass** if you don't want the item.
- The window shows the minimum and maximum bid for the item.

---

## How PUGs (or Anyone Without the Addon) Can Bid

You don't need the addon to bid. **Whisper the officer running the loot** with one of these commands. Officers can also allow these commands in raid or guild chat (`/dkp modes` -> **Modes** tab -> **Command Channels**). Replies always come back as a whisper.

| Type this | What it does |
|---|---|
| `!bid 50` | Bids 50 DKP on the current item. Use whatever number you want to bid. |
| `!bid` | In **Static Item Values** mode (or Zero-Sum with fixed prices), says you want the item at its set price. In Minimum Bid mode you need to include a number. |
| `!bid cancel` | Cancels your bid. (Doesn't work for rolls in Roll-Based mode.) |
| `!dkp` | Tells you how much DKP you have. |
| `!dkp PlayerName` | Tells you how much DKP another player has. |

**Passing:** If you don't want the item, just don't bid. (Players with the addon can also click **Pass** in their bid window.)

**Roll-Based Bidding:** If your guild uses Roll-Based mode, you don't whisper a number. Instead, type `/random` with your roll range. Whisper `!dkp` to the officer to find out what your range is.

---

## How the Standby List Works

When the raid is full, you'll often have players online and ready to swap in. The standby list lets you reward them for being available, so they don't fall behind on DKP.

### Adding players to standby

**Option 1: Officers add them by hand**

1. In the `/dkp` roster, select the players (Shift+Click to select more than one). They need to already be on the DKP table.
2. Right-click and choose **Manage Standby List** -> **Add Selected Players to Standby List**.
3. From the same menu you can also **Remove Selected Players from Standby List**, **Clear Standby List**, or **View Standby List**.

**Option 2: Players opt in by themselves**

1. An officer turns on **Standby Opt In** in `/dkp modes` -> **Options** tab.
2. After each boss kill, the addon clears the standby list and posts a message in guild chat asking benched players to opt in.
3. For the next **2 minutes**, players on the bench can type `!standby` in guild chat (or whisper it to the officer). If you're on an alt, type `!standby MainName` with your main's name spelled exactly.

If Auto Award DKP is on, the standby list's DKP goes out when those 2 minutes are up.

### How standby players get DKP

- **Raid Timer ticks:** tick **Include Standby** in the Raid Timer box on the **Adjust DKP** tab.
- **Automatic boss kills:** tick **Include Standby** under Auto Award DKP in `/dkp modes` -> **Options**.

Standby players get the same amount as the players in the raid. In Zero-Sum mode there's also an **Include Standby** box on the Zero-Sum bank. Keep in mind that splitting the pool with the bench means smaller shares for everyone.

---

## Officer Checklist

### Before the raid
- Open `/dkp` and look at the small status dot in the bottom-left corner.
  - **Green** means your tables are up to date.
  - **Red** means you're out of date. Ask the last officer who made changes to send a **Merge Last 2 Weeks** (or a **Full Broadcast**) to the guild.

### At the start of the raid
- Pick the right team from the **Team:** dropdown.
- Add any new players (**Manage** -> **Add Raid Members**).
- Update or clear the standby list.
- Start the **Raid Timer** (**Adjust DKP** -> **Initialize Raid**).

### During the raid
- Use the Bidding window to run and award loot (after each boss fight, not during it).
- Boss kill awards and Raid Timer ticks go out on their own. Anything that happens during a boss fight is held and sent when the fight ends.

### At the end of the raid
- Click **End Raid** on the **Adjust DKP** tab.
- Click the status dot in the bottom-left of `/dkp` to open the **Broadcast** window, tick **Guild** and **Merge Last 2 Weeks**, and click **Broadcast**. This catches up anyone who disconnected or logged in late.

### Weekly
- Apply **Weekly DKP Decay** on the **Adjust DKP** tab if your guild uses decay. Double-check the percentage first, because decay can't be undone.
- Remove players who have left the guild (**Manage** -> **Remove Entries**).
- If you keep records outside the game, use `/dkp export` to copy out your tables.

> **Merge Last 2 Weeks** only adds the entries other people are missing.
> **Full Broadcast** overwrites everyone else's tables with yours. Only use it if you're sure your copy is the right one.

---

## Slash Commands

`/commdkp` works the same as `/dkp`.

| Command | What it does |
|---|---|
| `/dkp` | Opens or closes the main DKP window. |
| `/dkp ?` | Lists the commands in chat. |
| `/dkp modes` | Opens the DKP Modes and Options window (officers only). |
| `/dkp settings` | Opens CommunityDKP Forever in the game's **Options -> AddOns** menu. |
| `/dkp bid [item link]` | Officers: opens the Bidding window, with the item filled in if you link one. Raiders: opens your bid window. |
| `/dkp award [item link]` | Officers: awards an item directly, without running a bid. |
| `/dkp timer <seconds> <title>` | Shows a countdown bar to the raid, e.g. `/dkp timer 120 Bio Break`. |
| `/dkp lockouts` | Shows when the raid lockouts reset. |
| `/dkp export` | Opens the export window. |
| `/dkp reset` | Moves the addon's windows back to the middle of the screen. |
| `/dkp test` | Guild Leader: runs the addon's self-test and prints the results in chat. |
| `/dkp trace` | Turns on chat logging of addon sync messages, for troubleshooting. Lasts until you log out. |

To move the bid timer bar, use the **Move Bid Timer** button on the **Options** tab.

---

## Tips and Backups

- **Back up your data.** Your DKP data is saved in `World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/CommunityDKPForever.lua`. Copying that file somewhere safe once a week means you can always recover if something goes wrong.
- **Share standings outside the game.** Use `/dkp export` at the end of the raid week and post the results to your guild's Discord or website.

---

CommunityDKP Forever continues CommunityDKP, which was forked from [MonolithDKP](https://www.curseforge.com/wow/addons/monolith-dkp). It has been rebuilt for World of Warcraft: Forever.
