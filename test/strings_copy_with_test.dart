import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rendel/rendel.dart';

/// `copyWith` once took 15 of the class's fields and rebuilt the rest from
/// the English defaults, so `RendelStrings.forLocale('tr').copyWith(confirm:
/// …)`, the pattern the dartdoc recommends, put "Send", "Copy" and "Back to
/// the assistant" under a Turkish answer.
///
/// [_fields] is every field, by name. The first test holds it to the class's
/// own declarations, so a field added to `RendelStrings` and not here fails;
/// the others pass each one through `copyWith` by name, so a field left out
/// of `copyWith` fails too.
final Map<String, Object Function(RendelStrings)> _fields = {
  'confirm': (s) => s.confirm,
  'goBack': (s) => s.goBack,
  'irreversible': (s) => s.irreversible,
  'emptyTitle': (s) => s.emptyTitle,
  'emptyBody': (s) => s.emptyBody,
  'working': (s) => s.working,
  'nothingHeard': (s) => s.nothingHeard,
  'dictationFailed': (s) => s.dictationFailed,
  'dictationDenied': (s) => s.dictationDenied,
  'openSettings': (s) => s.openSettings,
  'comparisonBest': (s) => s.comparisonBest,
  'cardEditInvalid': (s) => s.cardEditInvalid,
  'cardEditFailed': (s) => s.cardEditFailed,
  'cardLess': (s) => s.cardLess,
  'cardMore': (s) => s.cardMore,
  'composerHint': (s) => s.composerHint,
  'sendMessage': (s) => s.sendMessage,
  'newConversation': (s) => s.newConversation,
  'readAloud': (s) => s.readAloud,
  'autoRead': (s) => s.autoRead,
  'listen': (s) => s.listen,
  'readAloudThis': (s) => s.readAloudThis,
  'stopReading': (s) => s.stopReading,
  'retry': (s) => s.retry,
  'streamDropped': (s) => s.streamDropped,
  'noAnswer': (s) => s.noAnswer,
  'confirmationExpired': (s) => s.confirmationExpired,
  'turnFailed': (s) => s.turnFailed,
  'copilotStalled': (s) => s.copilotStalled,
  'attachFailed': (s) => s.attachFailed,
  'ratedHelpful': (s) => s.ratedHelpful,
  'ratedUnhelpful': (s) => s.ratedUnhelpful,
  'ratingChosenSuffix': (s) => s.ratingChosenSuffix,
  'yes': (s) => s.yes,
  'no': (s) => s.no,
  'testMode': (s) => s.testMode,
  'open': (s) => s.open,
  'choose': (s) => s.choose,
  'chooseDate': (s) => s.chooseDate,
  'chooseTime': (s) => s.chooseTime,
  'notChosen': (s) => s.notChosen,
  'send': (s) => s.send,
  'sending': (s) => s.sending,
  'sent': (s) => s.sent,
  'required': (s) => s.required,
  'optional': (s) => s.optional,
  'fieldRequired': (s) => s.fieldRequired,
  'fieldNumber': (s) => s.fieldNumber,
  'fieldSwitchRequired': (s) => s.fieldSwitchRequired,
  'formBusy': (s) => s.formBusy,
  'formFailed': (s) => s.formFailed,
  'expired': (s) => s.expired,
  'expiredBody': (s) => s.expiredBody,
  'confirmed': (s) => s.confirmed,
  'notAnswered': (s) => s.notAnswered,
  'notConfirmed': (s) => s.notConfirmed,
  'subtotal': (s) => s.subtotal,
  'tax': (s) => s.tax,
  'total': (s) => s.total,
  'loading': (s) => s.loading,
  'nothingToShow': (s) => s.nothingToShow,
  'dayHeading': (s) => s.dayHeading,
  'shortDays': (s) => s.shortDays,
  'shortMonths': (s) => s.shortMonths,
  'openCopilot': (s) => s.openCopilot,
  'closeCopilot': (s) => s.closeCopilot,
  'messageField': (s) => s.messageField,
  'attachFile': (s) => s.attachFile,
  'removeFile': (s) => s.removeFile,
  'speak': (s) => s.speak,
  'stopListening': (s) => s.stopListening,
  'holdToSpeak': (s) => s.holdToSpeak,
  'typeMessage': (s) => s.typeMessage,
  'photos': (s) => s.photos,
  'camera': (s) => s.camera,
  'files': (s) => s.files,
  'listening': (s) => s.listening,
  'stepOf': (s) => s.stepOf,
  'readoutIn': (s) => s.readoutIn,
  'readoutPeak': (s) => s.readoutPeak,
  'readoutNow': (s) => s.readoutNow,
  'readoutNowPeak': (s) => s.readoutNowPeak,
  'soldOut': (s) => s.soldOut,
  'statusThinking': (s) => s.statusThinking,
  'statusAction': (s) => s.statusAction,
  'statusComposing': (s) => s.statusComposing,
  'previousPage': (s) => s.previousPage,
  'nextPage': (s) => s.nextPage,
  'statusDetail': (s) => s.statusDetail,
  'detailAsk': (s) => s.detailAsk,
  'closeDetail': (s) => s.closeDetail,
  'backToAssistant': (s) => s.backToAssistant,
  'choiceSubmit': (s) => s.choiceSubmit,
  'choiceSend': (s) => s.choiceSend,
  'choiceCount': (s) => s.choiceCount,
  'copy': (s) => s.copy,
  'copied': (s) => s.copied,
  'reveal': (s) => s.reveal,
  'showMore': (s) => s.showMore,
  'asOf': (s) => s.asOf,
  'arrives': (s) => s.arrives,
  'inMinutes': (s) => s.inMinutes,
  'inHours': (s) => s.inHours,
  'tomorrowAt': (s) => s.tomorrowAt,
  'best': (s) => s.best,
  'uploadAdd': (s) => s.uploadAdd,
  'uploadAddPhoto': (s) => s.uploadAddPhoto,
  'uploadRemove': (s) => s.uploadRemove,
  'searchOptions': (s) => s.searchOptions,
  'dateRangeStart': (s) => s.dateRangeStart,
  'dateRangeEnd': (s) => s.dateRangeEnd,
  'previousMonth': (s) => s.previousMonth,
  'nextMonth': (s) => s.nextMonth,
  'fieldAtLeast': (s) => s.fieldAtLeast,
  'fieldAtMost': (s) => s.fieldAtMost,
  'fieldOnOrAfter': (s) => s.fieldOnOrAfter,
  'fieldOnOrBefore': (s) => s.fieldOnOrBefore,
  'ratingThanks': (s) => s.ratingThanks,
  'ratingStars': (s) => s.ratingStars,
  'ratingFrom': (s) => s.ratingFrom,
  'numberLocale': (s) => s.numberLocale,
  'thumbsUp': (s) => s.thumbsUp,
  'thumbsDown': (s) => s.thumbsDown,
  'helpful': (s) => s.helpful,
  'typeToConfirm': (s) => s.typeToConfirm,
  'typedMismatch': (s) => s.typedMismatch,
  'readAll': (s) => s.readAll,
  'readToConfirm': (s) => s.readToConfirm,
  'changes': (s) => s.changes,
  'currentUnavailable': (s) => s.currentUnavailable,
  'suggestedAfter': (s) => s.suggestedAfter,
  'expand': (s) => s.expand,
  'collapse': (s) => s.collapse,
  'directions': (s) => s.directions,
  'call': (s) => s.call,
  'openNow': (s) => s.openNow,
  'closed': (s) => s.closed,
  'openInMaps': (s) => s.openInMaps,
  'validUntil': (s) => s.validUntil,
  'passBoarding': (s) => s.passBoarding,
  'passTicket': (s) => s.passTicket,
  'passPickup': (s) => s.passPickup,
  'passCoupon': (s) => s.passCoupon,
  'passMembership': (s) => s.passMembership,
  'pro': (s) => s.pro,
  'con': (s) => s.con,
  'playVideo': (s) => s.playVideo,
  'copyCode': (s) => s.copyCode,
  'memorySaved': (s) => s.memorySaved,
  'memorySavedUntil': (s) => s.memorySavedUntil,
  'memoryNoted': (s) => s.memoryNoted,
  'memoryNotedUntil': (s) => s.memoryNotedUntil,
  'memoryUpdated': (s) => s.memoryUpdated,
  'memoryForgotten': (s) => s.memoryForgotten,
  'memoryForgottenAll': (s) => s.memoryForgottenAll,
  'memoryUndo': (s) => s.memoryUndo,
  'memoryUndone': (s) => s.memoryUndone,
  'memoryUsed': (s) => s.memoryUsed,
  'memoryUsedMany': (s) => s.memoryUsedMany,
  'memoryFromPreference': (s) => s.memoryFromPreference,
  'memoryTitle': (s) => s.memoryTitle,
  'memoryEmpty': (s) => s.memoryEmpty,
  'memoryForget': (s) => s.memoryForget,
  'memoryForgetAll': (s) => s.memoryForgetAll,
  'memoryForgetAllConfirm': (s) => s.memoryForgetAllConfirm,
  'memoryFromApp': (s) => s.memoryFromApp,
  'memoryNoticed': (s) => s.memoryNoticed,
  'memoryUntil': (s) => s.memoryUntil,
  'memoryFooter': (s) => s.memoryFooter,
  'memoryOff': (s) => s.memoryOff,
};

const _source = 'lib/src/core/strings.dart';
const _table = 'const Map<String, RendelStrings> _byLocale';

/// English, and every language the SDK ships, read from the table itself.
Map<String, RendelStrings> _languages() {
  final source = File(_source).readAsStringSync();
  final tags = RegExp(r"^  '([a-z-]+)': RendelStrings\(", multiLine: true)
      .allMatches(source.substring(source.indexOf(_table)))
      .map((m) => m.group(1)!);
  return {
    'en': const RendelStrings(),
    for (final tag in tags) tag: RendelStrings.forLocale(tag),
  };
}

void main() {
  test('the list names every field the class declares', () {
    final source = File(_source).readAsStringSync();
    final declared = RegExp(r'^  final (?:String|List<String>) (\w+);',
            multiLine: true)
        .allMatches(source.substring(
          source.indexOf('class RendelStrings {'),
          source.indexOf(_table),
        ))
        .map((m) => m.group(1)!)
        .toSet();
    expect(declared, isNotEmpty);
    expect(_fields.keys.toSet(), declared);
  });

  test('the table holds more than English', () {
    expect(
      _languages().keys,
      containsAll(['en', 'tr', 'de', 'fr', 'es', 'ar']),
    );
  });

  test('copyWith() keeps every field of every language', () {
    for (final MapEntry(key: tag, value: original) in _languages().entries) {
      final copy = original.copyWith();
      for (final MapEntry(key: name, value: read) in _fields.entries) {
        expect(read(copy), read(original), reason: '$tag.$name');
      }
    }
  });

  test('copyWith changes the one field it is given and keeps the rest', () {
    for (final MapEntry(key: tag, value: original) in _languages().entries) {
      for (final MapEntry(key: name, value: read) in _fields.entries) {
        final Object changed =
            read(original) is List ? const ['x'] : 'changed $name';
        final copy = Function.apply(
          original.copyWith,
          const [],
          {Symbol(name): changed},
        ) as RendelStrings;
        expect(read(copy), changed, reason: '$tag: copyWith($name: …)');
        for (final MapEntry(key: other, value: readOther) in _fields.entries) {
          if (other == name) continue;
          expect(
            readOther(copy),
            readOther(original),
            reason: '$tag: copyWith($name: …) lost $other',
          );
        }
      }
    }
  });
}
