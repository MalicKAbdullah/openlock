/// True for the F-Droid / IzzyOnDroid build (`--dart-define=OFFLYNE_STORE=fdroid`).
/// Those stores deliver updates themselves, so a store build has no update
/// check, banner or request. Absent, the flag is the GitHub build.
const bool kStoreBuild = String.fromEnvironment('OFFLYNE_STORE') == 'fdroid';
