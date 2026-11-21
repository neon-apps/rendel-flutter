import 'package:flutter/material.dart';

import '../core/strings.dart';
import 'renderer/blocks.dart' show RendelActionButton;
import 'theme.dart';

/// The site [url] would take the person to when it is none of the app's
/// [own] sites (security assessment 2026-11-20, decision 9; Tuna:
/// "Uyarıyla", the way ChatGPT asks before an unverified link): its host,
/// without `www.`. Null for the app's own sites, and for anything that is not
/// a web address.
///
/// [own] is `own_sites` from the app config: bare hosts, or `*.` and a domain
/// for it and its subdomains.
String? leavesOwnSites(String url, List<String> own) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  for (final entry in own) {
    final site = entry.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (site.startsWith('*.')) {
      final domain = site.substring(2);
      if (host == domain || host.endsWith('.$domain')) return null;
    } else if (host == site) {
      return null;
    }
  }
  return host;
}

/// "Open another site?" over the thread, naming [site], with Go back and
/// Open site. Whether the person chose to open it: a swipe down, a tap
/// beside the sheet or Go back opens nothing.
Future<bool> askToLeave(BuildContext context, String site, {RendelStrings? strings}) async {
  final theme = RendelThemeScope.of(context);
  final words = strings ?? RendelStringsScope.of(context);
  final open = await showModalBottomSheet<bool>(
    context: context,
    sheetAnimationStyle: rendelSheetMotion(context),
    useSafeArea: true,
    backgroundColor: theme.colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(theme.radius.hero)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => RendelThemeScope(
      theme: theme,
      child: RendelStringsScope(strings: words, child: RendelLeaveSheet(site: site)),
    ),
  );
  return open == true;
}

/// The sheet [askToLeave] shows: its title, one sentence with the site's
/// name in it, and the two buttons, Go back first.
class RendelLeaveSheet extends StatelessWidget {
  const RendelLeaveSheet({super.key, required this.site});

  /// The host the link goes to, without `www.`.
  final String site;

  @override
  Widget build(BuildContext context) {
    final theme = RendelThemeScope.of(context);
    final strings = RendelStringsScope.of(context);
    final parts = strings.leaveBody.split('{site}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(strings.leaveTitle, style: theme.text.title)),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: theme.text.body.copyWith(color: theme.colors.onSurfaceSoft),
              children: [
                TextSpan(text: parts.first),
                // Isolated, so a host reads left to right in an Arabic sentence.
                TextSpan(
                  text: '\u2066$site\u2069',
                  style: TextStyle(fontWeight: FontWeight.w600, color: theme.colors.onSurface),
                ),
                if (parts.length > 1) TextSpan(text: parts.sublist(1).join('{site}')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: RendelActionButton(
                  label: strings.goBack,
                  quiet: true,
                  expand: true,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RendelActionButton(
                  label: strings.leaveOpen,
                  expand: true,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
