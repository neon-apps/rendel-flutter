import 'package:flutter/widgets.dart';

/// Every word the SDK puts on screen that did not come from your app or from
/// the model.
///
/// They were literals scattered across the thread, the confirm card and the
/// error bar, which meant a copilot inside a Turkish app answered in Turkish
/// and then offered "Confirm" and "Go back" underneath it. The catalog is
/// drawn from the model's own words and the confirmation sentence comes from
/// your template — so this was the last English left, and it sat on the two
/// controls a user presses to authorise something.
///
/// Leave [RendelConfig.strings] null and the SDK picks these from the language it
/// is already answering in — [RendelConfig.locale], or the device's. That is the
/// whole fix for the paragraph above, and it needs no argument from the host.
///
/// Pass one to take over. Every field has an English default, so overriding
/// two is a two-line change rather than a translation project, and
/// [copyWith] on a built-in translation is how you change one word of a
/// language the SDK already ships:
///
/// ```dart
/// RendelConfig(
///   locale: 'tr-TR',
///   // Everything Turkish, except what this bank calls its own transfers.
///   strings: RendelStrings.forLocale('tr').copyWith(confirm: 'Transferi onayla'),
/// )
/// ```
///
/// Still deliberately not a `Localizations` delegate: the host tells us its
/// language in one field it was already setting, and asking it to register a
/// delegate on top of that would be a worse trade than reading the field.
@immutable
class RendelStrings {
  const RendelStrings({
    this.confirm = 'Confirm',
    this.goBack = 'Go back',
    this.irreversible = 'This cannot be undone',
    this.emptyTitle = 'Ask anything about this app.',
    this.emptyBody = 'Ask in your own words. One sentence is enough.',
    this.working = 'Working…',
    this.nothingHeard = 'Nothing was heard. Check the microphone and try again.',
    this.dictationFailed = 'Speech recognition is not available right now.',
    this.dictationDenied = 'Allow the microphone and speech recognition for this app in Settings to talk to the assistant.',
    this.openSettings = 'Open Settings',
    this.comparisonBest = 'Highlighted: the best in its row.',
    this.cardEditInvalid = 'That value can’t be used here.',
    this.cardEditFailed = 'That change didn’t go through. Try again.',
    this.cardLess = 'Fewer',
    this.cardMore = 'More',
    this.composerHint = 'Ask anything',
    this.sendMessage = 'Send message',
    this.newConversation = 'Start a new conversation',
    this.readAloud = 'Read answers aloud',
    this.retry = 'Try again',
    this.streamDropped = 'The connection dropped before the answer finished.',
    this.noAnswer = 'No answer came back. Try again.',
    this.confirmationExpired = 'That confirmation expired. Ask again and I will redo it.',
    this.turnFailed = 'Something failed while finishing that. Try again.',
    this.copilotStalled = 'The assistant stopped responding.',
    this.attachFailed = 'That file could not be attached.',
    this.ratedHelpful = 'This answer helped',
    this.ratedUnhelpful = 'This answer did not help',
    this.ratingChosenSuffix = ', chosen. Tap to undo.',
    this.yes = 'Yes',
    this.no = 'No',
    this.testMode = 'Test mode',
    this.open = 'Open',
    this.choose = 'Choose',
    this.chooseDate = 'Choose a date',
    this.chooseTime = 'Choose a time',
    this.notChosen = 'not chosen',
    this.send = 'Send',
    this.sending = 'Sending…',
    this.sent = 'Sent',
    this.required = 'Required',
    this.optional = 'Optional',
    this.fieldRequired = 'Fill this in to continue.',
    this.fieldNumber = 'Enter a number.',
    this.fieldSwitchRequired = 'Turn this on to continue.',
    this.formBusy = 'Still working on the last answer. Try again in a moment.',
    this.formFailed =
        'That did not send. Your answers are still here, so press {submit} to try again.',
    this.expired = 'Expired',
    this.expiredBody = 'Nothing was done. Ask again to start it over.',
    this.confirmed = 'Confirmed',
    this.notAnswered = 'Not answered',
    this.notConfirmed = 'Not confirmed',
    this.subtotal = 'Subtotal',
    this.tax = 'Tax',
    this.total = 'Total',
    this.loading = 'Loading',
    this.nothingToShow = 'Nothing to show.',
    this.dayHeading = '{day} {date} {month}',
    this.shortDays = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    this.shortMonths = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ],
    this.openCopilot = 'Open the assistant',
    this.closeCopilot = 'Close the assistant',
    this.messageField = 'Message',
    this.attachFile = 'Attach a file',
    this.removeFile = 'Remove {name}',
    this.speak = 'Speak instead of typing',
    this.stopListening = 'Stop listening',
    this.typeMessage = 'Type a message',
    this.photos = 'Photos',
    this.camera = 'Camera',
    this.files = 'Files',
    this.listening = 'Listening',
    this.stepOf = 'Step {step} of {count}',
    this.readoutIn = 'in {label}',
    this.readoutPeak = 'in {label}, the highest',
    this.readoutNow = '{label}',
    this.readoutNowPeak = '{label}, the highest',
    this.soldOut = 'Sold out: {labels}',
    this.statusThinking = 'Thinking…',
    this.statusAction = 'Checking your app…',
    this.statusComposing = 'Putting it together…',
    this.previousPage = 'Previous page',
    this.nextPage = 'Next page',
    this.statusDetail = 'Getting the details…',
    this.detailAsk = 'Tell me about {title}',
    this.closeDetail = 'Close',
    this.backToAssistant = 'Back to the assistant',
    this.choiceSubmit = 'Continue',
    this.choiceSend = 'Send',
    this.choiceCount = '{n} of {m} selected',
    this.copy = 'Copy',
    this.copied = 'Copied',
    this.reveal = 'Show',
    this.showMore = 'Show {n} more',
    this.asOf = 'as of {time}',
    this.arrives = 'Arrives {time}',
    this.inMinutes = 'in about {n} min',
    this.inHours = 'in {n} hours',
    this.tomorrowAt = 'tomorrow {time}',
    this.best = 'best',
    this.uploadAdd = 'Add a file',
    this.uploadAddPhoto = 'Add a photo',
    this.uploadRemove = 'Remove',
    this.searchOptions = 'Search',
    this.dateRangeStart = 'From',
    this.dateRangeEnd = 'To',
    this.previousMonth = 'Previous month',
    this.nextMonth = 'Next month',
    this.fieldAtLeast = 'Enter {min} or more.',
    this.fieldAtMost = 'Enter {max} or less.',
    this.fieldOnOrAfter = 'Pick {date} or later.',
    this.fieldOnOrBefore = 'Pick {date} or earlier.',
    this.ratingThanks = 'Thanks for telling us',
    this.ratingStars = '{n} of 5',
    this.thumbsUp = 'Good',
    this.thumbsDown = 'Not good',
    this.helpful = 'Helpful?',
    this.typeToConfirm = 'Type {value} to confirm',
    this.typedMismatch = 'That doesn\'t match. Type it exactly as shown.',
    this.readAll = 'Read all ({n} characters)',
    this.readToConfirm = 'Read it all to confirm',
    this.changes = 'Changes',
    this.currentUnavailable = 'The current text could not be loaded.',
    this.suggestedAfter = 'Suggested after reading {source}',
    this.expand = 'Show',
    this.collapse = 'Hide',
    this.directions = 'Directions',
    this.call = 'Call',
    this.openNow = 'Open now',
    this.closed = 'Closed',
    this.openInMaps = 'Open in Maps',
    this.validUntil = 'Valid until {date}',
    this.passBoarding = 'Boarding pass',
    this.passTicket = 'Ticket',
    this.passPickup = 'Pickup',
    this.passCoupon = 'Coupon',
    this.passMembership = 'Membership',
    this.pro = 'Pro',
    this.con = 'Con',
    this.playVideo = 'Play video',
    this.copyCode = 'Copy',
  });

  /// The two controls on a confirmation card. The ones that matter most.
  final String confirm;
  final String goBack;

  /// The warning above a destructive card.
  final String irreversible;

  /// The headline over an empty thread, and the line under it.
  ///
  /// These were literals in the widget, which meant a copilot answering in
  /// Turkish opened with an English sentence — the one screen in the product
  /// where the SDK speaks first. `RendelConfig.emptyStateBody` still overrides the
  /// second, because a customer's own words beat a translation of ours.
  final String emptyTitle;
  final String emptyBody;

  /// The composer's prompt while a turn is running. It replaces
  /// [composerHint] rather than sitting beside it, because the box is the one
  /// place a user looks to find out whether anything is happening.
  final String working;

  /// Shown when a dictation ends having captured nothing at all.
  ///
  /// Not decoration: a recogniser that cannot reach a microphone reports a
  /// clean, immediate end rather than an error, so without this the control
  /// opens and shuts under the user's finger and says nothing about why.
  final String nothingHeard;

  /// Shown when the host's `onDictate` throws rather than returning.
  ///
  /// The other way a dictation ends with nothing: not silence, but a
  /// recogniser that failed. The two shared one English sentence, which sent
  /// people to check a microphone that was fine.
  final String dictationFailed;

  /// Shown when the microphone or speech recognition was refused. Not
  /// [dictationFailed]: nothing is broken, the person has a switch to turn,
  /// and saying where it is beats saying it is unavailable (Grove report P1-9).
  final String dictationDenied;

  /// The button beside [dictationDenied] that opens this app's page in the
  /// system settings, where that switch is.
  final String openSettings;

  /// Under a comparison that marks a best value: what the mark means, which
  /// on its own read as "different" (Grove report).
  final String comparisonBest;

  /// Under a value changed on a confirmation card that the server refused.
  final String cardEditInvalid;

  /// Under a confirmation card whose change did not reach the server.
  final String cardEditFailed;

  /// The stepper's two buttons on a confirmation card, for a screen reader.
  final String cardLess;
  final String cardMore;

  final String composerHint;

  /// Screen-reader labels for the two controls with no visible text.
  final String sendMessage;
  final String newConversation;

  /// The header's speaker: whether answers are read aloud. A toggle, so a
  /// screen reader says on or off with it.
  final String readAloud;

  final String retry;
  final String streamDropped;
  final String noAnswer;
  final String confirmationExpired;

  /// The rest of the error bar's own sentences: a turn that ended in error
  /// without saying why, a stream that went quiet, a file the host's picker
  /// or the upload could not deliver.
  ///
  /// These were English literals in the controller and the thread, drawn
  /// under a Turkish answer next to a Turkish composer. What the server says
  /// in that bar arrives in the app's language already; these are the words
  /// that never left the SDK.
  final String turnFailed;
  final String copilotStalled;
  final String attachFailed;

  /// The per-turn rating controls.
  final String ratedHelpful;
  final String ratedUnhelpful;

  /// Appended to a rating's label once it is the chosen one.
  final String ratingChosenSuffix;

  /// Rendered for a boolean value in a detail row.
  final String yes;
  final String no;

  /// The badge in the header of a copilot on a test key.
  final String testMode;

  /// The catalog's own words: the default labels on a card's control, a
  /// picker's prompt, and the verbs a form goes through.
  ///
  /// The confirm buttons were the first to leave English; these were the
  /// rest of it. A Turkish form said "Required" beside every field and
  /// "Sending…" under the answers, and a receipt summed to "Total".
  final String open;
  final String choose;
  final String chooseDate;
  final String chooseTime;

  /// Spoken, not drawn: the state of a date field a screen reader announces.
  final String notChosen;

  /// A form's submit control, when the model gave it no label of its own:
  /// idle, in flight, and done.
  final String send;
  final String sending;
  final String sent;

  /// The flag beside a field that has to be filled in.
  final String required;

  /// The flag beside a field that may be left empty. Blocks v6 marks the
  /// optional fields of a form rather than the required ones.
  final String optional;

  /// What a form says under a field it will not send.
  final String fieldRequired;
  final String fieldNumber;
  final String fieldSwitchRequired;

  /// A form that could not be sent: the thread was busy, or the send failed.
  /// `{submit}` in [formFailed] is the submit control's label.
  final String formBusy;
  final String formFailed;

  /// A confirmation card's resolved states.
  final String expired;
  final String expiredBody;
  final String confirmed;
  final String notAnswered;
  final String notConfirmed;

  /// The summing rows of a receipt.
  final String subtotal;
  final String tax;
  final String total;

  /// Spoken over a block that has not arrived, and drawn over one that came
  /// back empty.
  final String loading;
  final String nothingToShow;

  /// The heading over a day's booking slots: `{day}`, `{date}` and `{month}`
  /// in the order the language puts them, from [shortDays] and
  /// [shortMonths].
  ///
  /// The SDK carries no date-formatting dependency, so these are the
  /// abbreviations by hand. A host that needs another calendar overrides all
  /// three.
  final String dayHeading;
  final List<String> shortDays;
  final List<String> shortMonths;

  /// What a screen reader calls the controls that have no visible text.
  /// `{name}` in [removeFile] is the file's name.
  final String openCopilot;
  final String closeCopilot;
  final String messageField;
  final String attachFile;
  final String removeFile;
  final String speak;
  final String stopListening;

  /// The composer at rest: the keyboard that opens the box, and the three
  /// places a file comes from, in the "+" menu and in the box.
  final String typeMessage;
  final String photos;
  final String camera;
  final String files;

  /// Voice mode, before the first word is heard.
  final String listening;

  /// The order tracker's bar: which step of how many. `{step}` and `{count}`
  /// are substituted.
  final String stepOf;

  /// The caption beside a bar chart's latest value: where it is (`{label}`),
  /// and the same when it is the highest in the chart.
  final String readoutIn;
  final String readoutPeak;

  /// The same, for a label that is itself a when ("Today", "This week"),
  /// which reads wrong after "in".
  final String readoutNow;
  final String readoutNowPeak;

  /// Under a variant picker, naming the options that cannot be chosen, so a
  /// sold-out size is said and not only drawn fainter. `{labels}` is them,
  /// joined.
  final String soldOut;

  /// The pill in the microphone's place while an answer page is on its way:
  /// thinking until the server says otherwise, then calling one of the app's
  /// actions, then drawing the page (`turn.status`).
  final String statusThinking;
  final String statusAction;
  final String statusComposing;

  /// The back and forward controls over an answer page.
  final String previousPage;
  final String nextPage;

  /// A card opened over its page (`design/DETAIL.md`): the pill while its
  /// detail is fetched, the question asked for a card that carries none of
  /// its own (`{title}` is the card's), and the control that closes it.
  final String statusDetail;
  final String detailAsk;
  final String closeDetail;

  /// The bubble the copilot shrinks into while a screen of the app it opened
  /// is showing (`design/NAVIGATE.md`): what a screen reader says it does.
  final String backToAssistant;

  /// A question answered by tapping (`design/CHOICE.md`): the button under a
  /// list of several picks when the model names none, the button beside the
  /// answer written in its own words, and what a screen reader hears as the
  /// picks change (`{n}` picked of `{m}`).
  final String choiceSubmit;
  final String choiceSend;
  final String choiceCount;

  /// Records the user takes something from (`design/CATALOG-B2.md`): what a
  /// screen reader calls a copy button, what the button says for a moment
  /// once it has copied, and what a masked account number's tap does.
  final String copy;
  final String copied;
  final String reveal;

  /// The quiet button under a long `item_list`, `{n}` being the rows it
  /// holds back.
  final String showMore;

  /// When a figure or an ETA was true (`{time}` a clock time), and when an
  /// order arrives (`{time}` a clock time, a window, or one of the phrases
  /// below).
  final String asOf;
  final String arrives;

  /// How soon something starts, while that is still true: within the hour
  /// and a half (`{n}` minutes, rounded), later today (`{n}` hours, two or
  /// more), or tomorrow (`{time}` its clock time).
  final String inMinutes;
  final String inHours;
  final String tomorrowAt;

  /// Said after the value a `comparison` row marks, which is otherwise only
  /// drawn.
  final String best;

  /// Form v2 (`design/FORM-V2.md`): the dashed tile an upload field adds a
  /// file or a photo with, what a screen reader calls the control that takes
  /// one away again, the search field over a long select, and the two halves
  /// of a date range.
  final String uploadAdd;
  final String uploadAddPhoto;
  final String uploadRemove;
  final String searchOptions;
  final String dateRangeStart;
  final String dateRangeEnd;

  /// A date field's month: what a screen reader calls the two buttons that
  /// turn it.
  final String previousMonth;
  final String nextMonth;

  /// What a form says under a number outside the field's `min` or `max`,
  /// with `{min}` or `{max}` the bound, and under a day outside its
  /// `min_date` or `max_date`, with `{date}` the bound. The web SDK's keys
  /// and words, so the two read alike.
  final String fieldAtLeast;
  final String fieldAtMost;
  final String fieldOnOrAfter;
  final String fieldOnOrBefore;

  /// Catalog wave 4 (`design/CATALOG-B4.md`): what a `rating` folds into
  /// once it is answered, and what a screen reader calls a star (`{n}` of
  /// five) and the two thumbs; and what a `disclosure` row's tap does, shut
  /// and open.
  final String ratingThanks;
  final String ratingStars;
  final String thumbsUp;
  final String thumbsDown;

  /// The answer page's thumbs (analytics-roi T1): the question beside them.
  final String helpful;

  /// A confirmation card that asks the user to type a value back ({value}),
  /// carries a long text ({n} characters) with what changes, or was drawn
  /// after reading what someone else wrote ({source}).
  final String typeToConfirm;
  final String typedMismatch;
  final String readAll;
  final String readToConfirm;
  final String changes;
  final String currentUnavailable;
  final String suggestedAfter;
  final String expand;
  final String collapse;

  /// Catalog wave 5 (`design/CATALOG-B5.md`): a `place_card`'s two buttons
  /// and whether it is open; the button under a full-screen `map` that hands
  /// a pin to the maps app; and a `pass`'s kind, as its overline, and its
  /// expiry (`{date}`).
  final String directions;
  final String call;
  final String openNow;
  final String closed;
  final String openInMaps;
  final String validUntil;
  final String passBoarding;
  final String passTicket;
  final String passPickup;
  final String passCoupon;
  final String passMembership;

  /// Catalog wave 6 (`design/CATALOG-B6.md`): what a screen reader says
  /// before a `key_points` pro or con, the name of a `media_gallery`
  /// picture's play button, and the button on a `code` block's head.
  final String pro;
  final String con;
  final String playVideo;
  final String copyCode;

  String formFailedWith(String submit) => formFailed.replaceAll('{submit}', submit);
  String removeFileNamed(String name) => removeFile.replaceAll('{name}', name);
  String detailAskAbout(String title) => detailAsk.replaceAll('{title}', title);
  String typeToConfirmFor(String value) => typeToConfirm.replaceAll('{value}', value);
  String readAllOf(String count) => readAll.replaceAll('{n}', count);
  String suggestedAfterFrom(String source) => suggestedAfter.replaceAll('{source}', source);
  String stepOfCount(int step, int count) =>
      stepOf.replaceAll('{step}', '$step').replaceAll('{count}', '$count');
  /// [now] for a label that is itself a when ("Today"): no "in" before it.
  String readoutAt(String label, {required bool peak, bool now = false}) =>
      (now ? (peak ? readoutNowPeak : readoutNow) : (peak ? readoutPeak : readoutIn))
          .replaceAll('{label}', label);
  String soldOutNamed(List<String> labels) =>
      soldOut.replaceAll('{labels}', labels.join(', '));
  String choiceCountOf(int n, int m) =>
      choiceCount.replaceAll('{n}', '$n').replaceAll('{m}', '$m');
  String showMoreCount(int n) => showMore.replaceAll('{n}', '$n');
  String asOfTime(String time) => asOf.replaceAll('{time}', time);
  String arrivesAt(String time) => arrives.replaceAll('{time}', time);
  String inMinutesCount(int n) => inMinutes.replaceAll('{n}', '$n');
  String inHoursCount(int n) => inHours.replaceAll('{n}', '$n');
  String tomorrowAtTime(String time) => tomorrowAt.replaceAll('{time}', time);
  String fieldAtLeastOf(String min) => fieldAtLeast.replaceAll('{min}', min);
  String fieldAtMostOf(String max) => fieldAtMost.replaceAll('{max}', max);
  String fieldOnOrAfterOf(String date) => fieldOnOrAfter.replaceAll('{date}', date);
  String fieldOnOrBeforeOf(String date) => fieldOnOrBefore.replaceAll('{date}', date);
  String ratingStarsOf(int n) => ratingStars.replaceAll('{n}', '$n');
  String validUntilDate(String date) => validUntil.replaceAll('{date}', date);

  /// The heading for a day, from a local time.
  String dayHeadingFor(DateTime local) => dayHeading
      .replaceAll('{day}', shortDays[local.weekday - 1])
      .replaceAll('{date}', '${local.day}')
      .replaceAll('{month}', shortMonths[local.month - 1]);

  /// The SDK's words for a language tag, or English for one it does not carry.
  ///
  /// Matched the same way `RendelAction.confirmTemplates` is matched on the server,
  /// because a copilot that takes its confirmation sentence from `pt-BR` and
  /// its Confirm button from English would be worse than one that is wholly
  /// English: the exact tag first, then the language, then any regional
  /// variant of that language the table happens to carry.
  ///
  /// The languages here are the ones the SDK ships. An app in any other
  /// language keeps today's behaviour — English chrome — and [copyWith] or a
  /// hand-written [RendelStrings] is how it stops.
  factory RendelStrings.forLocale(String? tag) {
    final normalised = tag?.trim().toLowerCase().replaceAll('_', '-');
    if (normalised == null || normalised.isEmpty) return const RendelStrings();

    final exact = _byLocale[normalised];
    if (exact != null) return exact;

    final language = normalised.split('-').first;
    final byLanguage = _byLocale[language];
    if (byLanguage != null) return byLanguage;

    for (final entry in _byLocale.entries) {
      if (entry.key.split('-').first == language) return entry.value;
    }
    return const RendelStrings();
  }

  /// One field of an existing set, changed. The rest are kept, which is what
  /// makes a shipped translation a starting point rather than a take-it-or-
  /// leave-it.
  ///
  /// Every field is a parameter. A field added to the class and not here
  /// would come back in English; `test/strings_copy_with_test.dart` fails if
  /// one is.
  RendelStrings copyWith({
    String? confirm,
    String? goBack,
    String? irreversible,
    String? emptyTitle,
    String? emptyBody,
    String? working,
    String? nothingHeard,
    String? dictationFailed,
    String? dictationDenied,
    String? openSettings,
    String? comparisonBest,
    String? cardEditInvalid,
    String? cardEditFailed,
    String? cardLess,
    String? cardMore,
    String? composerHint,
    String? sendMessage,
    String? newConversation,
    String? readAloud,
    String? retry,
    String? streamDropped,
    String? noAnswer,
    String? confirmationExpired,
    String? turnFailed,
    String? copilotStalled,
    String? attachFailed,
    String? ratedHelpful,
    String? ratedUnhelpful,
    String? ratingChosenSuffix,
    String? yes,
    String? no,
    String? testMode,
    String? open,
    String? choose,
    String? chooseDate,
    String? chooseTime,
    String? notChosen,
    String? send,
    String? sending,
    String? sent,
    String? required,
    String? optional,
    String? fieldRequired,
    String? fieldNumber,
    String? fieldSwitchRequired,
    String? formBusy,
    String? formFailed,
    String? expired,
    String? expiredBody,
    String? confirmed,
    String? notAnswered,
    String? notConfirmed,
    String? subtotal,
    String? tax,
    String? total,
    String? loading,
    String? nothingToShow,
    String? dayHeading,
    List<String>? shortDays,
    List<String>? shortMonths,
    String? openCopilot,
    String? closeCopilot,
    String? messageField,
    String? attachFile,
    String? removeFile,
    String? speak,
    String? stopListening,
    String? typeMessage,
    String? photos,
    String? camera,
    String? files,
    String? listening,
    String? stepOf,
    String? readoutIn,
    String? readoutPeak,
    String? readoutNow,
    String? readoutNowPeak,
    String? soldOut,
    String? statusThinking,
    String? statusAction,
    String? statusComposing,
    String? previousPage,
    String? nextPage,
    String? statusDetail,
    String? detailAsk,
    String? closeDetail,
    String? backToAssistant,
    String? choiceSubmit,
    String? choiceSend,
    String? choiceCount,
    String? copy,
    String? copied,
    String? reveal,
    String? showMore,
    String? asOf,
    String? arrives,
    String? inMinutes,
    String? inHours,
    String? tomorrowAt,
    String? best,
    String? uploadAdd,
    String? uploadAddPhoto,
    String? uploadRemove,
    String? searchOptions,
    String? dateRangeStart,
    String? dateRangeEnd,
    String? previousMonth,
    String? nextMonth,
    String? fieldAtLeast,
    String? fieldAtMost,
    String? fieldOnOrAfter,
    String? fieldOnOrBefore,
    String? ratingThanks,
    String? ratingStars,
    String? thumbsUp,
    String? thumbsDown,
    String? helpful,
    String? typeToConfirm,
    String? typedMismatch,
    String? readAll,
    String? readToConfirm,
    String? changes,
    String? currentUnavailable,
    String? suggestedAfter,
    String? expand,
    String? collapse,
    String? directions,
    String? call,
    String? openNow,
    String? closed,
    String? openInMaps,
    String? validUntil,
    String? passBoarding,
    String? passTicket,
    String? passPickup,
    String? passCoupon,
    String? passMembership,
    String? pro,
    String? con,
    String? playVideo,
    String? copyCode,
  }) {
    return RendelStrings(
      confirm: confirm ?? this.confirm,
      goBack: goBack ?? this.goBack,
      irreversible: irreversible ?? this.irreversible,
      emptyTitle: emptyTitle ?? this.emptyTitle,
      emptyBody: emptyBody ?? this.emptyBody,
      working: working ?? this.working,
      nothingHeard: nothingHeard ?? this.nothingHeard,
      dictationFailed: dictationFailed ?? this.dictationFailed,
      dictationDenied: dictationDenied ?? this.dictationDenied,
      openSettings: openSettings ?? this.openSettings,
      comparisonBest: comparisonBest ?? this.comparisonBest,
      cardEditInvalid: cardEditInvalid ?? this.cardEditInvalid,
      cardEditFailed: cardEditFailed ?? this.cardEditFailed,
      cardLess: cardLess ?? this.cardLess,
      cardMore: cardMore ?? this.cardMore,
      composerHint: composerHint ?? this.composerHint,
      sendMessage: sendMessage ?? this.sendMessage,
      newConversation: newConversation ?? this.newConversation,
      readAloud: readAloud ?? this.readAloud,
      retry: retry ?? this.retry,
      streamDropped: streamDropped ?? this.streamDropped,
      noAnswer: noAnswer ?? this.noAnswer,
      confirmationExpired: confirmationExpired ?? this.confirmationExpired,
      turnFailed: turnFailed ?? this.turnFailed,
      copilotStalled: copilotStalled ?? this.copilotStalled,
      attachFailed: attachFailed ?? this.attachFailed,
      ratedHelpful: ratedHelpful ?? this.ratedHelpful,
      ratedUnhelpful: ratedUnhelpful ?? this.ratedUnhelpful,
      ratingChosenSuffix: ratingChosenSuffix ?? this.ratingChosenSuffix,
      yes: yes ?? this.yes,
      no: no ?? this.no,
      testMode: testMode ?? this.testMode,
      open: open ?? this.open,
      choose: choose ?? this.choose,
      chooseDate: chooseDate ?? this.chooseDate,
      chooseTime: chooseTime ?? this.chooseTime,
      notChosen: notChosen ?? this.notChosen,
      send: send ?? this.send,
      sending: sending ?? this.sending,
      sent: sent ?? this.sent,
      required: required ?? this.required,
      optional: optional ?? this.optional,
      fieldRequired: fieldRequired ?? this.fieldRequired,
      fieldNumber: fieldNumber ?? this.fieldNumber,
      fieldSwitchRequired: fieldSwitchRequired ?? this.fieldSwitchRequired,
      formBusy: formBusy ?? this.formBusy,
      formFailed: formFailed ?? this.formFailed,
      expired: expired ?? this.expired,
      expiredBody: expiredBody ?? this.expiredBody,
      confirmed: confirmed ?? this.confirmed,
      notAnswered: notAnswered ?? this.notAnswered,
      notConfirmed: notConfirmed ?? this.notConfirmed,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      nothingToShow: nothingToShow ?? this.nothingToShow,
      dayHeading: dayHeading ?? this.dayHeading,
      shortDays: shortDays ?? this.shortDays,
      shortMonths: shortMonths ?? this.shortMonths,
      openCopilot: openCopilot ?? this.openCopilot,
      closeCopilot: closeCopilot ?? this.closeCopilot,
      messageField: messageField ?? this.messageField,
      attachFile: attachFile ?? this.attachFile,
      removeFile: removeFile ?? this.removeFile,
      speak: speak ?? this.speak,
      stopListening: stopListening ?? this.stopListening,
      typeMessage: typeMessage ?? this.typeMessage,
      photos: photos ?? this.photos,
      camera: camera ?? this.camera,
      files: files ?? this.files,
      listening: listening ?? this.listening,
      stepOf: stepOf ?? this.stepOf,
      readoutIn: readoutIn ?? this.readoutIn,
      readoutPeak: readoutPeak ?? this.readoutPeak,
      readoutNow: readoutNow ?? this.readoutNow,
      readoutNowPeak: readoutNowPeak ?? this.readoutNowPeak,
      soldOut: soldOut ?? this.soldOut,
      statusThinking: statusThinking ?? this.statusThinking,
      statusAction: statusAction ?? this.statusAction,
      statusComposing: statusComposing ?? this.statusComposing,
      previousPage: previousPage ?? this.previousPage,
      nextPage: nextPage ?? this.nextPage,
      statusDetail: statusDetail ?? this.statusDetail,
      detailAsk: detailAsk ?? this.detailAsk,
      closeDetail: closeDetail ?? this.closeDetail,
      backToAssistant: backToAssistant ?? this.backToAssistant,
      choiceSubmit: choiceSubmit ?? this.choiceSubmit,
      choiceSend: choiceSend ?? this.choiceSend,
      choiceCount: choiceCount ?? this.choiceCount,
      copy: copy ?? this.copy,
      copied: copied ?? this.copied,
      reveal: reveal ?? this.reveal,
      showMore: showMore ?? this.showMore,
      asOf: asOf ?? this.asOf,
      arrives: arrives ?? this.arrives,
      inMinutes: inMinutes ?? this.inMinutes,
      inHours: inHours ?? this.inHours,
      tomorrowAt: tomorrowAt ?? this.tomorrowAt,
      best: best ?? this.best,
      uploadAdd: uploadAdd ?? this.uploadAdd,
      uploadAddPhoto: uploadAddPhoto ?? this.uploadAddPhoto,
      uploadRemove: uploadRemove ?? this.uploadRemove,
      searchOptions: searchOptions ?? this.searchOptions,
      dateRangeStart: dateRangeStart ?? this.dateRangeStart,
      dateRangeEnd: dateRangeEnd ?? this.dateRangeEnd,
      previousMonth: previousMonth ?? this.previousMonth,
      nextMonth: nextMonth ?? this.nextMonth,
      fieldAtLeast: fieldAtLeast ?? this.fieldAtLeast,
      fieldAtMost: fieldAtMost ?? this.fieldAtMost,
      fieldOnOrAfter: fieldOnOrAfter ?? this.fieldOnOrAfter,
      fieldOnOrBefore: fieldOnOrBefore ?? this.fieldOnOrBefore,
      ratingThanks: ratingThanks ?? this.ratingThanks,
      ratingStars: ratingStars ?? this.ratingStars,
      thumbsUp: thumbsUp ?? this.thumbsUp,
      thumbsDown: thumbsDown ?? this.thumbsDown,
      helpful: helpful ?? this.helpful,
      typeToConfirm: typeToConfirm ?? this.typeToConfirm,
      typedMismatch: typedMismatch ?? this.typedMismatch,
      readAll: readAll ?? this.readAll,
      readToConfirm: readToConfirm ?? this.readToConfirm,
      changes: changes ?? this.changes,
      currentUnavailable: currentUnavailable ?? this.currentUnavailable,
      suggestedAfter: suggestedAfter ?? this.suggestedAfter,
      expand: expand ?? this.expand,
      collapse: collapse ?? this.collapse,
      directions: directions ?? this.directions,
      call: call ?? this.call,
      openNow: openNow ?? this.openNow,
      closed: closed ?? this.closed,
      openInMaps: openInMaps ?? this.openInMaps,
      validUntil: validUntil ?? this.validUntil,
      passBoarding: passBoarding ?? this.passBoarding,
      passTicket: passTicket ?? this.passTicket,
      passPickup: passPickup ?? this.passPickup,
      passCoupon: passCoupon ?? this.passCoupon,
      passMembership: passMembership ?? this.passMembership,
      pro: pro ?? this.pro,
      con: con ?? this.con,
      playVideo: playVideo ?? this.playVideo,
      copyCode: copyCode ?? this.copyCode,
    );
  }
}

/// ———————————————————————— the shipped languages ————————————————————————
///
/// Written by the engineer who built the feature, not by a translator. They
/// are better than English under a Turkish answer, which is what they replace,
/// and they are **not** reviewed copy: `confirm`, `goBack` and `irreversible`
/// sit on a destructive action's authorisation, where a word that means nearly
/// the right thing is a consent problem rather than a typo. Have a native
/// speaker read those three before a customer in that language goes live, and
/// override with [RendelStrings.copyWith] until they have.
const Map<String, RendelStrings> _byLocale = {
  'tr': RendelStrings(
    nothingHeard: 'Hiçbir şey duyulmadı. Mikrofonu kontrol edip tekrar deneyin.',
    dictationFailed: 'Konuşma tanıma şu anda kullanılamıyor.',
    dictationDenied: "Asistanla konuşmak için Ayarlar'da bu uygulamaya mikrofon ve konuşma tanıma izni verin.",
    openSettings: 'Ayarları aç',
    comparisonBest: 'İşaretli: satırının en iyisi.',
    cardEditInvalid: 'Bu değer burada kullanılamaz.',
    cardEditFailed: 'Bu değişiklik iletilemedi. Tekrar deneyin.',
    cardLess: 'Azalt',
    cardMore: 'Artır',
    working: 'Çalışıyor…',
    emptyTitle: 'Bu uygulamayla ilgili ne isterseniz sorun.',
    emptyBody: 'Kendi cümlelerinizle sorun. Bir cümle yeterli.',
    confirm: 'Onayla',
    goBack: 'Geri',
    irreversible: 'Bu işlem geri alınamaz',
    composerHint: 'Ne isterseniz sorun',
    sendMessage: 'Mesajı gönder',
    newConversation: 'Yeni bir sohbet başlat',
    readAloud: 'Cevapları sesli oku',
    retry: 'Tekrar dene',
    streamDropped: 'Bağlantı, yanıt tamamlanmadan koptu.',
    noAnswer: 'Yanıt gelmedi. Tekrar deneyin.',
    confirmationExpired: 'Bu onayın süresi doldu. Tekrar sorun, yeniden yapayım.',
    turnFailed: 'Bu yanıt tamamlanırken bir şey ters gitti. Tekrar deneyin.',
    copilotStalled: 'Asistan yanıt vermeyi bıraktı.',
    attachFailed: 'Bu dosya eklenemedi.',
    ratedHelpful: 'Bu yanıt işime yaradı',
    ratedUnhelpful: 'Bu yanıt işime yaramadı',
    ratingChosenSuffix: ', seçildi. Geri almak için dokunun.',
    yes: 'Evet',
    no: 'Hayır',
    testMode: 'Test modu',
    open: 'Aç',
    choose: 'Seç',
    chooseDate: 'Bir tarih seçin',
    chooseTime: 'Bir saat seçin',
    notChosen: 'seçilmedi',
    send: 'Gönder',
    sending: 'Gönderiliyor…',
    sent: 'Gönderildi',
    required: 'Zorunlu',
    optional: 'İsteğe bağlı',
    stepOf: 'Adım {step} / {count}',
    readoutIn: '{label} döneminde',
    readoutPeak: '{label} döneminde, en yüksek',
    readoutNow: '{label}',
    readoutNowPeak: '{label}, en yüksek',
    soldOut: 'Tükendi: {labels}',
    fieldRequired: 'Devam etmek için bunu doldurun.',
    fieldNumber: 'Bir sayı girin.',
    fieldSwitchRequired: 'Devam etmek için bunu açın.',
    formBusy: 'Önceki yanıt hâlâ hazırlanıyor. Birazdan tekrar deneyin.',
    formFailed:
        'Gönderilemedi. Yanıtlarınız duruyor; tekrar denemek için {submit} düğmesine basın.',
    expired: 'Süresi doldu',
    expiredBody: 'Hiçbir şey yapılmadı. Baştan başlatmak için tekrar sorun.',
    confirmed: 'Onaylandı',
    notAnswered: 'Yanıtlanmadı',
    notConfirmed: 'Onaylanmadı',
    subtotal: 'Ara toplam',
    tax: 'Vergi',
    total: 'Toplam',
    loading: 'Yükleniyor',
    nothingToShow: 'Gösterilecek bir şey yok.',
    dayHeading: '{date} {month} {day}',
    shortDays: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'],
    shortMonths: [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ],
    openCopilot: 'Asistanı aç',
    closeCopilot: 'Asistanı kapat',
    messageField: 'Mesaj',
    attachFile: 'Dosya ekle',
    removeFile: '{name} dosyasını kaldır',
    speak: 'Yazmak yerine konuşun',
    stopListening: 'Dinlemeyi durdur',
    typeMessage: 'Mesaj yaz',
    photos: 'Fotoğraflar',
    camera: 'Kamera',
    files: 'Dosyalar',
    listening: 'Dinliyorum',
    statusThinking: 'Düşünüyor…',
    statusAction: 'Uygulamanda bakılıyor…',
    statusComposing: 'Sayfa hazırlanıyor…',
    previousPage: 'Önceki sayfa',
    nextPage: 'Sonraki sayfa',
    statusDetail: 'Ayrıntılar getiriliyor…',
    detailAsk: '{title} hakkında bilgi ver',
    closeDetail: 'Kapat',
    backToAssistant: 'Asistana dön',
    choiceSubmit: 'Devam',
    choiceSend: 'Gönder',
    choiceCount: '{m} seçenekten {n} tanesi seçili',
    copy: 'Kopyala',
    copied: 'Kopyalandı',
    reveal: 'Göster',
    showMore: '{n} tane daha göster',
    asOf: '{time} itibarıyla',
    arrives: 'Varış {time}',
    inMinutes: 'yaklaşık {n} dk içinde',
    inHours: '{n} saat içinde',
    tomorrowAt: 'yarın {time}',
    best: 'en iyisi',
    uploadAdd: 'Dosya ekle',
    uploadAddPhoto: 'Fotoğraf ekle',
    uploadRemove: 'Kaldır',
    searchOptions: 'Ara',
    dateRangeStart: 'Başlangıç',
    dateRangeEnd: 'Bitiş',
    previousMonth: 'Önceki ay',
    nextMonth: 'Sonraki ay',
    fieldAtLeast: '{min} veya daha fazlasını girin.',
    fieldAtMost: '{max} veya daha azını girin.',
    fieldOnOrAfter: '{date} veya sonrasını seçin.',
    fieldOnOrBefore: '{date} veya öncesini seçin.',
    ratingThanks: 'Bildirdiğin için teşekkürler',
    ratingStars: '5 üzerinden {n}',
    thumbsUp: 'İyi',
    thumbsDown: 'İyi değil',
    helpful: 'Faydalı mı?',
    typeToConfirm: 'Onaylamak için aşağıdaki alana tam olarak şunu yazın: {value}',
    typedMismatch: 'Girilen metin eşleşmedi. Gösterilen ifadeyi harfi harfine yazın.',
    readAll: 'Tamamını oku ({n} karakter)',
    readToConfirm: 'Onaylamak için metnin tamamını okuyun.',
    changes: 'Değişiklikler',
    currentUnavailable: 'Mevcut metin yüklenemedi.',
    suggestedAfter: 'İncelendikten sonra önerildi: {source}',
    expand: 'Göster',
    collapse: 'Gizle',
    directions: 'Yol tarifi',
    call: 'Ara',
    openNow: 'Şu an açık',
    closed: 'Kapalı',
    openInMaps: 'Haritalarda aç',
    validUntil: '{date} tarihine kadar geçerli',
    passBoarding: 'Biniş kartı',
    passTicket: 'Bilet',
    passPickup: 'Teslim alma',
    passCoupon: 'Kupon',
    passMembership: 'Üyelik',
    pro: 'Artı',
    con: 'Eksi',
    playVideo: 'Videoyu oynat',
    copyCode: 'Kopyala',
  ),
  'de': RendelStrings(
    nothingHeard: 'Es wurde nichts gehört. Prüfen Sie das Mikrofon.',
    dictationFailed: 'Die Spracherkennung ist gerade nicht verfügbar.',
    dictationDenied: 'Erlauben Sie in den Einstellungen Mikrofon und Spracherkennung für diese App, um mit dem Assistenten zu sprechen.',
    openSettings: 'Einstellungen öffnen',
    comparisonBest: 'Markiert: der beste Wert der Zeile.',
    cardEditInvalid: 'Dieser Wert ist hier nicht möglich.',
    cardEditFailed: 'Die Änderung kam nicht an. Versuchen Sie es erneut.',
    cardLess: 'Weniger',
    cardMore: 'Mehr',
    working: 'Arbeitet…',
    emptyTitle: 'Fragen Sie alles über diese App.',
    emptyBody: 'Fragen Sie in Ihren eigenen Worten. Ein Satz genügt.',
    confirm: 'Bestätigen',
    goBack: 'Zurück',
    irreversible: 'Das kann nicht rückgängig gemacht werden',
    composerHint: 'Stellen Sie Ihre Frage',
    sendMessage: 'Nachricht senden',
    newConversation: 'Neue Unterhaltung beginnen',
    readAloud: 'Antworten vorlesen',
    retry: 'Erneut versuchen',
    streamDropped: 'Die Verbindung wurde vor dem Ende der Antwort unterbrochen.',
    noAnswer: 'Es kam keine Antwort. Versuchen Sie es erneut.',
    confirmationExpired:
        'Diese Bestätigung ist abgelaufen. Fragen Sie erneut, dann mache ich es noch einmal.',
    turnFailed: 'Beim Abschließen ist etwas fehlgeschlagen. Versuchen Sie es erneut.',
    copilotStalled: 'Der Assistent antwortet nicht mehr.',
    attachFailed: 'Diese Datei konnte nicht angehängt werden.',
    ratedHelpful: 'Diese Antwort hat geholfen',
    ratedUnhelpful: 'Diese Antwort hat nicht geholfen',
    ratingChosenSuffix: ', ausgewählt. Zum Rückgängigmachen tippen.',
    yes: 'Ja',
    no: 'Nein',
    testMode: 'Testmodus',
    open: 'Öffnen',
    choose: 'Auswählen',
    chooseDate: 'Datum wählen',
    chooseTime: 'Uhrzeit wählen',
    notChosen: 'nicht gewählt',
    send: 'Senden',
    sending: 'Wird gesendet…',
    sent: 'Gesendet',
    required: 'Erforderlich',
    optional: 'Optional',
    stepOf: 'Schritt {step} von {count}',
    readoutIn: 'bei {label}',
    readoutPeak: 'bei {label}, der höchste Wert',
    readoutNow: '{label}',
    readoutNowPeak: '{label}, der höchste Wert',
    soldOut: 'Ausverkauft: {labels}',
    fieldRequired: 'Füllen Sie dies aus, um fortzufahren.',
    fieldNumber: 'Geben Sie eine Zahl ein.',
    fieldSwitchRequired: 'Schalten Sie dies ein, um fortzufahren.',
    formBusy:
        'Die letzte Antwort wird noch bearbeitet. Versuchen Sie es gleich erneut.',
    formFailed:
        'Das wurde nicht gesendet. Ihre Angaben sind noch da; drücken Sie {submit}, um es erneut zu versuchen.',
    expired: 'Abgelaufen',
    expiredBody: 'Es wurde nichts ausgeführt. Fragen Sie erneut, um von vorn zu beginnen.',
    confirmed: 'Bestätigt',
    notAnswered: 'Nicht beantwortet',
    notConfirmed: 'Nicht bestätigt',
    subtotal: 'Zwischensumme',
    tax: 'Steuern',
    total: 'Gesamt',
    loading: 'Wird geladen',
    nothingToShow: 'Nichts anzuzeigen.',
    dayHeading: '{day} {date}. {month}',
    shortDays: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
    shortMonths: [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
    ],
    openCopilot: 'Assistenten öffnen',
    closeCopilot: 'Assistenten schließen',
    messageField: 'Nachricht',
    attachFile: 'Datei anhängen',
    removeFile: '{name} entfernen',
    speak: 'Sprechen statt tippen',
    stopListening: 'Zuhören beenden',
    typeMessage: 'Nachricht schreiben',
    photos: 'Fotos',
    camera: 'Kamera',
    files: 'Dateien',
    listening: 'Hört zu',
    statusThinking: 'Denkt nach…',
    statusAction: 'Ihre App wird geprüft…',
    statusComposing: 'Seite wird erstellt…',
    previousPage: 'Vorherige Seite',
    nextPage: 'Nächste Seite',
    statusDetail: 'Details werden geladen…',
    detailAsk: 'Erzähl mir mehr über {title}',
    closeDetail: 'Schließen',
    backToAssistant: 'Zurück zum Assistenten',
    choiceSubmit: 'Weiter',
    choiceSend: 'Senden',
    choiceCount: '{n} von {m} ausgewählt',
    copy: 'Kopieren',
    copied: 'Kopiert',
    reveal: 'Anzeigen',
    showMore: '{n} weitere anzeigen',
    asOf: 'Stand {time}',
    arrives: 'Ankunft {time}',
    inMinutes: 'in etwa {n} Min.',
    inHours: 'in {n} Stunden',
    tomorrowAt: 'morgen {time}',
    best: 'der beste Wert',
    uploadAdd: 'Datei hinzufügen',
    uploadAddPhoto: 'Foto hinzufügen',
    uploadRemove: 'Entfernen',
    searchOptions: 'Suchen',
    dateRangeStart: 'Von',
    dateRangeEnd: 'Bis',
    previousMonth: 'Vorheriger Monat',
    nextMonth: 'Nächster Monat',
    fieldAtLeast: 'Geben Sie {min} oder mehr ein.',
    fieldAtMost: 'Geben Sie {max} oder weniger ein.',
    fieldOnOrAfter: 'Wählen Sie {date} oder später.',
    fieldOnOrBefore: 'Wählen Sie {date} oder früher.',
    ratingThanks: 'Danke für Ihre Rückmeldung',
    ratingStars: '{n} von 5',
    thumbsUp: 'Gut',
    thumbsDown: 'Nicht gut',
    helpful: 'Hilfreich?',
    typeToConfirm: 'Geben Sie {value} ein, um zu bestätigen',
    typedMismatch: 'Das stimmt nicht überein. Geben Sie es genau so ein.',
    readAll: 'Alles lesen ({n} Zeichen)',
    readToConfirm: 'Lesen Sie alles, um zu bestätigen',
    changes: 'Änderungen',
    currentUnavailable: 'Der aktuelle Text konnte nicht geladen werden.',
    suggestedAfter: 'Vorgeschlagen nach dem Lesen von {source}',
    expand: 'Anzeigen',
    collapse: 'Ausblenden',
    directions: 'Route',
    call: 'Anrufen',
    openNow: 'Jetzt geöffnet',
    closed: 'Geschlossen',
    openInMaps: 'In Karten öffnen',
    validUntil: 'Gültig bis {date}',
    passBoarding: 'Bordkarte',
    passTicket: 'Ticket',
    passPickup: 'Abholung',
    passCoupon: 'Gutschein',
    passMembership: 'Mitgliedschaft',
    pro: 'Pro',
    con: 'Contra',
    playVideo: 'Video abspielen',
    copyCode: 'Kopieren',
  ),
  'fr': RendelStrings(
    nothingHeard: "Rien n'a été entendu. Vérifiez le microphone.",
    dictationFailed: 'La reconnaissance vocale est indisponible pour le moment.',
    dictationDenied: "Autorisez le micro et la reconnaissance vocale pour cette app dans Réglages pour parler à l'assistant.",
    openSettings: 'Ouvrir Réglages',
    comparisonBest: 'En surbrillance : le meilleur de la ligne.',
    cardEditInvalid: 'Cette valeur n’est pas possible ici.',
    cardEditFailed: 'La modification n’est pas passée. Réessayez.',
    cardLess: 'Moins',
    cardMore: 'Plus',
    working: 'En cours…',
    emptyTitle: 'Posez toutes vos questions sur cette application.',
    emptyBody: 'Posez votre question avec vos mots. Une phrase suffit.',
    confirm: 'Confirmer',
    goBack: 'Retour',
    irreversible: 'Cette action est irréversible',
    composerHint: 'Posez votre question',
    sendMessage: 'Envoyer le message',
    newConversation: 'Démarrer une nouvelle conversation',
    readAloud: 'Lire les réponses à voix haute',
    retry: 'Réessayer',
    streamDropped: 'La connexion a été perdue avant la fin de la réponse.',
    noAnswer: 'Aucune réponse n’est arrivée. Réessayez.',
    confirmationExpired:
        'Cette confirmation a expiré. Redemandez et je recommence.',
    turnFailed: 'Quelque chose a échoué en terminant cette réponse. Réessayez.',
    copilotStalled: 'L’assistant a cessé de répondre.',
    attachFailed: 'Ce fichier n’a pas pu être joint.',
    ratedHelpful: 'Cette réponse m’a aidé',
    ratedUnhelpful: 'Cette réponse ne m’a pas aidé',
    ratingChosenSuffix: ', sélectionné. Touchez pour annuler.',
    yes: 'Oui',
    no: 'Non',
    testMode: 'Mode test',
    open: 'Ouvrir',
    choose: 'Choisir',
    chooseDate: 'Choisir une date',
    chooseTime: 'Choisir une heure',
    notChosen: 'non choisi',
    send: 'Envoyer',
    sending: 'Envoi…',
    sent: 'Envoyé',
    required: 'Obligatoire',
    optional: 'Facultatif',
    stepOf: 'Étape {step} sur {count}',
    readoutIn: 'en {label}',
    readoutPeak: 'en {label}, le plus élevé',
    readoutNow: '{label}',
    readoutNowPeak: '{label}, le plus élevé',
    soldOut: 'Épuisé : {labels}',
    fieldRequired: 'Remplissez ce champ pour continuer.',
    fieldNumber: 'Saisissez un nombre.',
    fieldSwitchRequired: 'Activez ceci pour continuer.',
    formBusy: 'La dernière réponse est encore en cours. Réessayez dans un instant.',
    formFailed:
        'L’envoi a échoué. Vos réponses sont conservées ; appuyez sur {submit} pour réessayer.',
    expired: 'Expiré',
    expiredBody: 'Rien n’a été fait. Redemandez pour recommencer.',
    confirmed: 'Confirmé',
    notAnswered: 'Sans réponse',
    notConfirmed: 'Non confirmé',
    subtotal: 'Sous-total',
    tax: 'Taxes',
    total: 'Total',
    loading: 'Chargement',
    nothingToShow: 'Rien à afficher.',
    dayHeading: '{day} {date} {month}',
    shortDays: ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'],
    shortMonths: [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
    ],
    openCopilot: 'Ouvrir l’assistant',
    closeCopilot: 'Fermer l’assistant',
    messageField: 'Message',
    attachFile: 'Joindre un fichier',
    removeFile: 'Retirer {name}',
    speak: 'Parler au lieu d’écrire',
    stopListening: 'Arrêter l’écoute',
    typeMessage: 'Écrire un message',
    photos: 'Photos',
    camera: 'Appareil photo',
    files: 'Fichiers',
    listening: 'À l’écoute',
    statusThinking: 'Réflexion…',
    statusAction: 'Vérification dans votre app…',
    statusComposing: 'Préparation de la page…',
    previousPage: 'Page précédente',
    nextPage: 'Page suivante',
    statusDetail: 'Récupération des détails…',
    detailAsk: 'Parle-moi de {title}',
    closeDetail: 'Fermer',
    backToAssistant: 'Retour à l’assistant',
    choiceSubmit: 'Continuer',
    choiceSend: 'Envoyer',
    choiceCount: '{n} sur {m} sélectionnés',
    copy: 'Copier',
    copied: 'Copié',
    reveal: 'Afficher',
    showMore: 'Afficher {n} de plus',
    asOf: 'à {time}',
    arrives: 'Arrivée {time}',
    inMinutes: 'dans environ {n} min',
    inHours: 'dans {n} heures',
    tomorrowAt: 'demain {time}',
    best: 'le meilleur',
    uploadAdd: 'Ajouter un fichier',
    uploadAddPhoto: 'Ajouter une photo',
    uploadRemove: 'Retirer',
    searchOptions: 'Rechercher',
    dateRangeStart: 'Du',
    dateRangeEnd: 'Au',
    previousMonth: 'Mois précédent',
    nextMonth: 'Mois suivant',
    fieldAtLeast: 'Saisissez {min} ou plus.',
    fieldAtMost: 'Saisissez {max} ou moins.',
    fieldOnOrAfter: 'Choisissez le {date} ou plus tard.',
    fieldOnOrBefore: 'Choisissez le {date} ou plus tôt.',
    ratingThanks: 'Merci de nous l’avoir dit',
    ratingStars: '{n} sur 5',
    thumbsUp: 'Bien',
    thumbsDown: 'Pas bien',
    helpful: 'Utile ?',
    typeToConfirm: 'Saisissez {value} pour confirmer',
    typedMismatch: 'Ce n’est pas identique. Saisissez-le exactement comme indiqué.',
    readAll: 'Tout lire ({n} caractères)',
    readToConfirm: 'Lisez tout pour confirmer',
    changes: 'Modifications',
    currentUnavailable: 'Le texte actuel n’a pas pu être chargé.',
    suggestedAfter: 'Suggéré après la lecture de {source}',
    expand: 'Afficher',
    collapse: 'Masquer',
    directions: 'Itinéraire',
    call: 'Appeler',
    openNow: 'Ouvert maintenant',
    closed: 'Fermé',
    openInMaps: 'Ouvrir dans Cartes',
    validUntil: 'Valable jusqu’au {date}',
    passBoarding: 'Carte d’embarquement',
    passTicket: 'Billet',
    passPickup: 'Retrait',
    passCoupon: 'Bon de réduction',
    passMembership: 'Adhésion',
    pro: 'Pour',
    con: 'Contre',
    playVideo: 'Lire la vidéo',
    copyCode: 'Copier',
  ),
  'es': RendelStrings(
    nothingHeard: 'No se oyó nada. Comprueba el micrófono.',
    dictationFailed: 'El reconocimiento de voz no está disponible ahora.',
    dictationDenied: 'Permite el micrófono y el reconocimiento de voz para esta app en Ajustes para hablar con el asistente.',
    openSettings: 'Abrir Ajustes',
    comparisonBest: 'Resaltado: el mejor de su fila.',
    cardEditInvalid: 'Ese valor no se puede usar aquí.',
    cardEditFailed: 'El cambio no se aplicó. Inténtalo de nuevo.',
    cardLess: 'Menos',
    cardMore: 'Más',
    working: 'Trabajando…',
    emptyTitle: 'Pregunta lo que quieras sobre esta aplicación.',
    emptyBody: 'Pregunta con tus propias palabras. Basta una frase.',
    confirm: 'Confirmar',
    goBack: 'Volver',
    irreversible: 'Esto no se puede deshacer',
    composerHint: 'Pregunta lo que quieras',
    sendMessage: 'Enviar mensaje',
    newConversation: 'Iniciar una conversación nueva',
    readAloud: 'Leer las respuestas en voz alta',
    retry: 'Inténtalo de nuevo',
    streamDropped: 'La conexión se cortó antes de terminar la respuesta.',
    noAnswer: 'No llegó ninguna respuesta. Inténtalo de nuevo.',
    confirmationExpired: 'Esa confirmación caducó. Vuelve a pedirlo y lo repito.',
    turnFailed: 'Algo falló al terminar esa respuesta. Inténtalo de nuevo.',
    copilotStalled: 'El asistente dejó de responder.',
    attachFailed: 'No se pudo adjuntar ese archivo.',
    ratedHelpful: 'Esta respuesta me ayudó',
    ratedUnhelpful: 'Esta respuesta no me ayudó',
    ratingChosenSuffix: ', seleccionado. Toca para deshacer.',
    yes: 'Sí',
    no: 'No',
    testMode: 'Modo de prueba',
    open: 'Abrir',
    choose: 'Elegir',
    chooseDate: 'Elige una fecha',
    chooseTime: 'Elige una hora',
    notChosen: 'sin elegir',
    send: 'Enviar',
    sending: 'Enviando…',
    sent: 'Enviado',
    required: 'Obligatorio',
    optional: 'Opcional',
    stepOf: 'Paso {step} de {count}',
    readoutIn: 'en {label}',
    readoutPeak: 'en {label}, el más alto',
    readoutNow: '{label}',
    readoutNowPeak: '{label}, el más alto',
    soldOut: 'Agotado: {labels}',
    fieldRequired: 'Rellena esto para continuar.',
    fieldNumber: 'Escribe un número.',
    fieldSwitchRequired: 'Activa esto para continuar.',
    formBusy: 'La última respuesta aún está en curso. Inténtalo de nuevo en un momento.',
    formFailed:
        'No se envió. Tus respuestas siguen aquí; pulsa {submit} para intentarlo de nuevo.',
    expired: 'Caducado',
    expiredBody: 'No se hizo nada. Vuelve a pedirlo para empezar de nuevo.',
    confirmed: 'Confirmado',
    notAnswered: 'Sin respuesta',
    notConfirmed: 'No confirmado',
    subtotal: 'Subtotal',
    tax: 'Impuestos',
    total: 'Total',
    loading: 'Cargando',
    nothingToShow: 'Nada que mostrar.',
    dayHeading: '{day} {date} {month}',
    shortDays: ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'],
    shortMonths: [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sept', 'oct', 'nov', 'dic',
    ],
    openCopilot: 'Abrir el asistente',
    closeCopilot: 'Cerrar el asistente',
    messageField: 'Mensaje',
    attachFile: 'Adjuntar un archivo',
    removeFile: 'Quitar {name}',
    speak: 'Hablar en lugar de escribir',
    stopListening: 'Dejar de escuchar',
    typeMessage: 'Escribir un mensaje',
    photos: 'Fotos',
    camera: 'Cámara',
    files: 'Archivos',
    listening: 'Escuchando',
    statusThinking: 'Pensando…',
    statusAction: 'Revisando tu app…',
    statusComposing: 'Preparando la página…',
    previousPage: 'Página anterior',
    nextPage: 'Página siguiente',
    statusDetail: 'Obteniendo los detalles…',
    detailAsk: 'Háblame de {title}',
    closeDetail: 'Cerrar',
    backToAssistant: 'Volver al asistente',
    choiceSubmit: 'Continuar',
    choiceSend: 'Enviar',
    choiceCount: '{n} de {m} seleccionados',
    copy: 'Copiar',
    copied: 'Copiado',
    reveal: 'Mostrar',
    showMore: 'Mostrar {n} más',
    asOf: 'a las {time}',
    arrives: 'Llega {time}',
    inMinutes: 'en unos {n} min',
    inHours: 'en {n} horas',
    tomorrowAt: 'mañana {time}',
    best: 'el mejor',
    uploadAdd: 'Añadir un archivo',
    uploadAddPhoto: 'Añadir una foto',
    uploadRemove: 'Quitar',
    searchOptions: 'Buscar',
    dateRangeStart: 'Desde',
    dateRangeEnd: 'Hasta',
    previousMonth: 'Mes anterior',
    nextMonth: 'Mes siguiente',
    fieldAtLeast: 'Escribe {min} o más.',
    fieldAtMost: 'Escribe {max} o menos.',
    fieldOnOrAfter: 'Elige el {date} o una fecha posterior.',
    fieldOnOrBefore: 'Elige el {date} o una fecha anterior.',
    ratingThanks: 'Gracias por contárnoslo',
    ratingStars: '{n} de 5',
    thumbsUp: 'Bien',
    thumbsDown: 'Mal',
    helpful: '¿Te ha servido?',
    typeToConfirm: 'Escribe {value} para confirmar',
    typedMismatch: 'No coincide. Escríbelo exactamente como se muestra.',
    readAll: 'Leer todo ({n} caracteres)',
    readToConfirm: 'Léelo todo para confirmar',
    changes: 'Cambios',
    currentUnavailable: 'No se pudo cargar el texto actual.',
    suggestedAfter: 'Sugerido después de leer {source}',
    expand: 'Mostrar',
    collapse: 'Ocultar',
    directions: 'Cómo llegar',
    call: 'Llamar',
    openNow: 'Abierto ahora',
    closed: 'Cerrado',
    openInMaps: 'Abrir en Mapas',
    validUntil: 'Válido hasta el {date}',
    passBoarding: 'Tarjeta de embarque',
    passTicket: 'Entrada',
    passPickup: 'Recogida',
    passCoupon: 'Cupón',
    passMembership: 'Membresía',
    pro: 'A favor',
    con: 'En contra',
    playVideo: 'Reproducir vídeo',
    copyCode: 'Copiar',
  ),
  'ar': RendelStrings(
    nothingHeard: 'لم يُسمع شيء. تحقّق من الميكروفون.',
    dictationFailed: 'التعرّف على الكلام غير متاح حاليًا.',
    dictationDenied: 'اسمح للتطبيق باستخدام الميكروفون والتعرّف على الكلام من الإعدادات للتحدث مع المساعد.',
    openSettings: 'فتح الإعدادات',
    comparisonBest: 'المظلَّل: الأفضل في صفّه.',
    cardEditInvalid: 'لا يمكن استخدام هذه القيمة هنا.',
    cardEditFailed: 'لم يصل هذا التغيير. حاول مرة أخرى.',
    cardLess: 'أقل',
    cardMore: 'أكثر',
    working: 'جارٍ العمل…',
    emptyTitle: 'اسأل أي شيء عن هذا التطبيق.',
    emptyBody: 'اسأل بكلماتك الخاصة. جملة واحدة تكفي.',
    confirm: 'تأكيد',
    goBack: 'رجوع',
    irreversible: 'لا يمكن التراجع عن هذا',
    composerHint: 'اسأل عن أي شيء',
    sendMessage: 'إرسال الرسالة',
    newConversation: 'بدء محادثة جديدة',
    readAloud: 'قراءة الإجابات بصوت عالٍ',
    retry: 'حاول مرة أخرى',
    streamDropped: 'انقطع الاتصال قبل أن تكتمل الإجابة.',
    noAnswer: 'لم تصل أي إجابة. حاول مرة أخرى.',
    confirmationExpired: 'انتهت صلاحية هذا التأكيد. اسأل مرة أخرى وسأعيد تنفيذه.',
    turnFailed: 'حدث خطأ أثناء إكمال ذلك. حاول مرة أخرى.',
    copilotStalled: 'توقّف المساعد عن الاستجابة.',
    attachFailed: 'تعذّر إرفاق هذا الملف.',
    ratedHelpful: 'هذه الإجابة كانت مفيدة',
    ratedUnhelpful: 'هذه الإجابة لم تكن مفيدة',
    ratingChosenSuffix: '، تم الاختيار. اضغط للتراجع.',
    yes: 'نعم',
    no: 'لا',
    testMode: 'وضع الاختبار',
    open: 'فتح',
    choose: 'اختيار',
    chooseDate: 'اختر تاريخًا',
    chooseTime: 'اختر وقتًا',
    notChosen: 'لم يُختر',
    send: 'إرسال',
    sending: 'جارٍ الإرسال…',
    sent: 'تم الإرسال',
    required: 'مطلوب',
    optional: 'اختياري',
    stepOf: 'الخطوة {step} من {count}',
    readoutIn: 'في {label}',
    readoutPeak: 'في {label}، الأعلى',
    readoutNow: '{label}',
    readoutNowPeak: '{label}، الأعلى',
    soldOut: 'نفد: {labels}',
    fieldRequired: 'املأ هذا الحقل للمتابعة.',
    fieldNumber: 'أدخل رقمًا.',
    fieldSwitchRequired: 'فعّل هذا للمتابعة.',
    formBusy: 'ما زالت الإجابة الأخيرة قيد الإعداد. حاول مرة أخرى بعد قليل.',
    formFailed: 'لم يتم الإرسال. إجاباتك ما زالت هنا؛ اضغط {submit} للمحاولة مرة أخرى.',
    expired: 'انتهت الصلاحية',
    expiredBody: 'لم يُنفَّذ شيء. اسأل مرة أخرى للبدء من جديد.',
    confirmed: 'تم التأكيد',
    notAnswered: 'بلا إجابة',
    notConfirmed: 'لم يتم التأكيد',
    subtotal: 'المجموع الفرعي',
    tax: 'الضريبة',
    total: 'الإجمالي',
    loading: 'جارٍ التحميل',
    nothingToShow: 'لا شيء لعرضه.',
    dayHeading: '{day} {date} {month}',
    shortDays: ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
    shortMonths: [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ],
    openCopilot: 'فتح المساعد',
    closeCopilot: 'إغلاق المساعد',
    messageField: 'الرسالة',
    attachFile: 'إرفاق ملف',
    removeFile: 'إزالة {name}',
    speak: 'تحدّث بدلًا من الكتابة',
    stopListening: 'إيقاف الاستماع',
    typeMessage: 'اكتب رسالة',
    photos: 'الصور',
    camera: 'الكاميرا',
    files: 'الملفات',
    listening: 'جارٍ الاستماع',
    statusThinking: 'جارٍ التفكير…',
    statusAction: 'جارٍ التحقق من تطبيقك…',
    statusComposing: 'جارٍ تجهيز الصفحة…',
    previousPage: 'الصفحة السابقة',
    nextPage: 'الصفحة التالية',
    statusDetail: 'جارٍ جلب التفاصيل…',
    detailAsk: 'أخبرني عن {title}',
    closeDetail: 'إغلاق',
    backToAssistant: 'العودة إلى المساعد',
    choiceSubmit: 'متابعة',
    choiceSend: 'إرسال',
    choiceCount: 'تم اختيار {n} من {m}',
    copy: 'نسخ',
    copied: 'تم النسخ',
    reveal: 'إظهار',
    showMore: 'عرض {n} أخرى',
    asOf: 'حتى {time}',
    arrives: 'الوصول {time}',
    inMinutes: 'خلال {n} دقيقة تقريبًا',
    inHours: 'خلال {n} ساعات',
    tomorrowAt: 'غدًا {time}',
    best: 'الأفضل',
    uploadAdd: 'أضف ملفًا',
    uploadAddPhoto: 'أضف صورة',
    uploadRemove: 'إزالة',
    searchOptions: 'بحث',
    dateRangeStart: 'من',
    dateRangeEnd: 'إلى',
    previousMonth: 'الشهر السابق',
    nextMonth: 'الشهر التالي',
    fieldAtLeast: 'أدخل {min} أو أكثر.',
    fieldAtMost: 'أدخل {max} أو أقل.',
    fieldOnOrAfter: 'اختر {date} أو تاريخًا لاحقًا.',
    fieldOnOrBefore: 'اختر {date} أو تاريخًا سابقًا.',
    ratingThanks: 'شكرًا لإخبارنا',
    ratingStars: '{n} من 5',
    thumbsUp: 'جيد',
    thumbsDown: 'غير جيد',
    helpful: 'هل كان هذا مفيدًا؟',
    typeToConfirm: 'اكتب {value} للتأكيد',
    typedMismatch: 'لا يتطابق. اكتبه تمامًا كما هو معروض.',
    readAll: 'اقرأ الكل ({n} حرفًا)',
    readToConfirm: 'اقرأه كله للتأكيد',
    changes: 'التغييرات',
    currentUnavailable: 'تعذّر تحميل النص الحالي.',
    suggestedAfter: 'مقترح بعد قراءة {source}',
    expand: 'إظهار',
    collapse: 'إخفاء',
    directions: 'الاتجاهات',
    call: 'اتصال',
    openNow: 'مفتوح الآن',
    closed: 'مغلق',
    openInMaps: 'فتح في الخرائط',
    validUntil: 'صالح حتى {date}',
    passBoarding: 'بطاقة صعود الطائرة',
    passTicket: 'تذكرة',
    passPickup: 'استلام',
    passCoupon: 'قسيمة',
    passMembership: 'عضوية',
    pro: 'ميزة',
    con: 'عيب',
    playVideo: 'تشغيل الفيديو',
    copyCode: 'نسخ',
  ),
};

/// Makes the host's strings reachable from a renderer.
///
/// The same shape as `RendelThemeScope`, and for the same reason: a component
/// deep in the catalog needs them and threading them through every builder
/// would be a parameter on every block in the product.
///
/// Absent, [of] returns the English defaults, so the gallery and every widget
/// test keep working without arranging anything.
class RendelStringsScope extends InheritedWidget {
  const RendelStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final RendelStrings strings;

  static RendelStrings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RendelStringsScope>()?.strings ??
      const RendelStrings();

  @override
  bool updateShouldNotify(RendelStringsScope oldWidget) =>
      oldWidget.strings != strings;
}
