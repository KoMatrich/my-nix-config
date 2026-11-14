# Supply-chain hardening for npm: a compromised package should not get code
# execution (and so ~/.ssh, tokens, the browser profile) just by being
# installed.
#
#  - ignore-scripts: dependencies' preinstall/install/postinstall hooks do not
#    run. That is how nearly every npm worm so far has executed.
#  - min-release-age: versions younger than N days are not installed. Malicious
#    releases are typically caught and unpublished within hours to days.
#
# This is npm's *global* config, the lowest-priority layer, so a project can
# still opt out in its own .npmrc, and ~/.npmrc stays writable for `npm login`.
# Applies to every npm, including the ones from project dev shells, because it
# is selected through the environment rather than the node package.
#
# A package that really needs its build step (native addons: sharp, esbuild,
# better-sqlite3, ...):   npm rebuild --ignore-scripts=false <package>
# A fresh release needed right now:   npm install --min-release-age=0 <package>
#
# This does not sandbox code you then *run* (npm test, a dev server); that
# needs a container - see the devbox / ClankerJail branches.
{ ... }:
{
  environment.etc."npmrc".text = ''
    ignore-scripts=true
    min-release-age=7
  '';
  environment.variables.NPM_CONFIG_GLOBALCONFIG = "/etc/npmrc";
}
