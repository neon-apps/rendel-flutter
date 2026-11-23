import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../core/strings.dart';

/// The host's Material words, when it has any: the SDK carries no date
/// library, so a month's name and a day said in full come from them.
///
/// Only when they are in the language the copilot is speaking. An app that
/// never loaded Turkish Material words still has English ones, and a Turkish
/// conversation then showed "Dec 15" and "December 2026"; the SDK's own words
/// say "15 Ara" and "Aralık 2026".
MaterialLocalizations? rendelMaterialWords(BuildContext context) {
  final host = Localizations.maybeLocaleOf(context);
  if (host == null) return null;
  final speaking = RendelStringsScope.of(context).shortMonths;
  if (!listEquals(RendelStrings.forLocale(host.toLanguageTag()).shortMonths, speaking)) return null;
  return Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
}

/// A text field's copy and paste menu, in the conversation's language.
///
/// The phone's menu takes its words from the host's Material and Cupertino
/// words, so the same English-only app offered "Copy" and "Paste" under a
/// Turkish answer. Where the host's words are the conversation's, the menu is
/// left exactly as the platform draws it.
///
/// Read from the field's own context: the menu is built in the overlay, above
/// the copilot's strings.
Widget rendelContextMenu(BuildContext context, EditableTextState field) {
  if (rendelMaterialWords(field.context) != null) {
    return AdaptiveTextSelectionToolbar.editableText(editableTextState: field);
  }
  final strings = RendelStringsScope.of(field.context);
  String? said(ContextMenuButtonType type) => switch (type) {
        ContextMenuButtonType.cut => strings.menuCut,
        ContextMenuButtonType.copy => strings.menuCopy,
        ContextMenuButtonType.paste => strings.menuPaste,
        ContextMenuButtonType.selectAll => strings.menuSelectAll,
        ContextMenuButtonType.delete => strings.menuDelete,
        ContextMenuButtonType.lookUp => strings.menuLookUp,
        ContextMenuButtonType.searchWeb => strings.menuSearchWeb,
        ContextMenuButtonType.share => strings.menuShare,
        ContextMenuButtonType.liveTextInput => strings.menuScanText,
        ContextMenuButtonType.custom => null,
      };
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: field.contextMenuAnchors,
    buttonItems: [
      for (final item in field.contextMenuButtonItems) item.label == null ? item.copyWith(label: said(item.type)) : item,
    ],
  );
}
