(async function () {
  'use strict';

  var statuses = document.querySelectorAll('[data-ios-status]');
  if (!statuses.length) return;

  try {
    var response = await fetch('/altstore.json');
    if (!response.ok) throw new Error('Could not check for the iOS release');
    var source = await response.json();
    var app = (source.apps || []).find(function (item) {
      return item.bundleIdentifier === 'com.nirmal.inzx';
    });
    var latest = app && app.versions && app.versions[0];
    if (!latest) {
      statuses.forEach(function (status) { status.textContent = 'The public iOS IPA is pending.'; });
      return;
    }

    statuses.forEach(function (status) {
      status.textContent = 'iOS ' + latest.version +
        (latest.buildVersion ? ' (build ' + latest.buildVersion + ')' : '') +
        ' is available to sideload.';
    });
    document.querySelectorAll('[data-ios-available]').forEach(function (element) { element.hidden = false; });
    document.querySelectorAll('[data-ios-ipa]').forEach(function (link) {
      link.href = latest.downloadURL;
      link.hidden = false;
    });
  } catch (_) {
    statuses.forEach(function (status) {
      status.textContent = 'Could not check iOS download availability. Check GitHub Releases.';
    });
  }
})();
