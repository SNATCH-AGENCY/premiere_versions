# Premiere Versions

**Less risk of losing your work. More peace of mind for every edit.**

Premiere Versions is a small macOS companion for Adobe Premiere Pro. It keeps a history of saved project files, so an accidental overwrite, a broken project or a change you regret does not have to mean starting over.

Its purpose is simple: **help protect important edits with deliberate version saves and automatic backup checkpoints.** Keeping those copies organized makes it easier to find a useful point to return to.

## A safety net for your projects

- **Save important milestones.** Keep a numbered copy before a major change, a client revision or a new direction. Add a short comment so you remember what changed.
- **Keep backups in the background.** While the app is running and backup monitoring is enabled, it discovers projects created within the last 48 hours and keeps recent, hourly and daily checkpoints. Enrolled projects remain protected after that window.
- **Find your way back.** Manual versions have readable names and comments; backup names include the project, checkpoint type and time.
- **Keep your archive manageable.** Older automatic backups rotate. Your manual versions stay until you decide to remove them. Original project files and Premiere’s own Auto-Saves are left untouched.

## Get started

1. Download the **DMG installer** from [Releases](https://github.com/pewakkk/premiere_versions/releases/latest), open it and **drag Premiere Versions.app onto Applications**. Open the app from Applications, then eject the installer.
2. Choose your Premiere project and allow access to the folders you want to use. Enable backup monitoring in Settings.
3. Save your latest changes in Premiere Pro with **Command+S**.
4. With Premiere Pro active, press **Option+S**, choose a version number, then press Return. Add an optional comment and press Return again to keep the copy.

The shortcut can be changed in Settings. You can also open the utility from the Dock or enable its optional menu bar icon.

## Which projects get automatic backups?

New automatic discovery uses the **file creation date within the last 48 hours**, not the last edit date. The project you explicitly select is protected regardless of age. Older unrelated projects do not create new archive folders. If creation time is unavailable, an untracked file is skipped. Projects already enrolled, including existing managed backup archives, continue to be backed up afterwards.

**No internet connection is needed for project discovery or copying.** The next scan can find projects created during an offline period, as long as they are still within the 48-hour window. The app must be running to monitor changes. Manual numbered saves remain available for projects of any age.

## What is protected?

Premiere Versions copies the **project file already saved on disk**. It cannot capture edits you have not saved in Premiere. Copies do not include your footage, audio or other linked media.

Keep your media backed up too. For protection against a drive failure, choose a backup location on a different drive.

## Make it yours

Choose English or Russian, your save locations and a built-in or custom icon. Your choices stay with you when you update.

The app quietly checks for updates at launch and every six hours. Use **Check updates** in Settings any time; you choose when to install. You can hide the Dock icon and keep the app in the menu bar instead.

## How backup history works

A first copy is made as soon as a stable saved project is found. Later changed states are copied no more often than once every **five minutes**. The archive keeps **10 recent different states**, **12 hourly checkpoints** and **5 daily checkpoints**. Checkpoints can share one physical file when the project has not changed, so an idle project does not fill your archive with duplicates.

Completed copies are checked before old managed copies are removed. Original files and unrelated files are never rotated. Projects with the same name from different locations receive separate folders such as `Project`, `Project_1` and `Project_2`.

The optional **latest Premiere autosave** switch keeps one matching file from the project's neighboring `Adobe Premiere Pro Auto-Save` folder. This copy has its own subfolder, separate from the utility's history. Premiere's original autosaves remain untouched.

## Keep the shortcut available

**Premiere Versions Helper**, the optional background shortcut helper, can open the installed utility after you quit it, while Premiere Pro is active. macOS may ask you to allow its background item. The helper only listens for the configured shortcut; **backup monitoring still requires the main utility to be running**. Your existing shortcut and preferences are preserved.

## Latest improvements

- **Smarter backup history.** Ten recent changed states at five-minute intervals, twelve hourly checkpoints and five daily checkpoints share copies without filling the archive with identical files.
- **Premiere Auto-Save protection.** Optionally keep the latest matching Premiere autosave in a separate folder alongside your backups.
- **Reliable project organization.** Selected projects stay protected at any age; projects with the same name from different locations receive separate, remembered folders.
- **A shortcut that stays available.** An optional background helper opens the utility from active Premiere Pro even after the utility has quit.
- Safer copy verification and cleanup, plus reduced repeated disk reads.

## Your work stays yours

Projects and backups stay in the folders you choose. Project files, comments and folder paths are not uploaded by the app. Update checks contact GitHub to look for new releases.

---

Want to build or contribute? See [development notes](DEVELOPMENT.md). For most people, the ready-to-use app in [Releases](https://github.com/pewakkk/premiere_versions/releases/latest) is all you need.
