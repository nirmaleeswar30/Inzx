import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations_x.dart';
import 'platform_utils.dart';

/// Closes the app so an update applies on the next start. iOS doesn't let an
/// app close itself (SystemNavigator.pop is ignored there), so it asks the
/// user to swipe it away instead.
void closeAppForUpdate(BuildContext context) {
  if (!isIOS) {
    SystemNavigator.pop();
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(context.l10n.iosReopenToApply),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
