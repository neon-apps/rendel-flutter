# Changelog

All notable changes to `rendel` (before 0.32.0, `neon_copilot`) are recorded here. The package follows
semantic versioning: while the version is below 1.0.0 a minor bump may carry a
breaking change, and each one is listed under **Breaking** with the edit it
asks of you.

## 0.65.0

**Changed**

- An answer flows in at one pace, as Monogram's does (Özlem 2026-10-28: ours
  came "tak tak tak", a paragraph at a time, each in a burst of its own).
  The page has one writer: its words come in at 110 characters a second, a
  long paragraph faster so none takes over four seconds, and each paragraph,
  card and section enters once the words above it are written, top to
  bottom. A `==marked==` phrase is no brighter than its words. A text that
  streams in keeps the same pace as more arrives, with the caret held back
  until the words so far are in. Under reduced motion everything is simply
  there, as before.

## 0.64.1

**Fixed**

- A voice whose stream fell behind was heard as a crackle (Özlem 2026-10-28:
  a 288 ms hole mid-word on a recording): the speaker ran dry and was then
  fed a tenth of a second at a time, stopping and starting on each. Once the
  speaker runs dry the voice gathers half a second again before going on, as
  it did to begin, so a stall is one pause.

## 0.64.0

**Fixed**

- An answer's `**bold**` arrived as its asterisks (Özlem 2026-10-28: the
  Cilt365 lede read "**Dehidrate Yağlı Cilt**", in every app). A text block
  now reads its inline marks as the web SDK and the console do: `**bold**`,
  `*italic*`, `` `code` ``, `~~struck~~` and `[words](https://…)`, which
  opens where its words are tapped, beside the `==phrase==` mark it already
  drew. The words arrive one after another in their own style, and a pair
  left unclosed stays as written.

## 0.63.5

**Fixed**

- The first answer's voice was cut after one breath (Özlem 2026-10-28). The
  three-second clock for the first sound ran from the request to the first
  feed, and the first answer after a cold start had half a second of its
  voice in at 2.8 s, opened the speaker past 3, and was cut. The clock now
  waits for the first bytes, and for each piece until the first sound, three
  seconds from the last; once the speaker is open nothing is cut.
- The audio session is taken after the speaker opens, not before: the PCM
  plugin sets a bare playback category of its own on opening, which took the
  spoken-audio mode and the ducking of other sound with it. Playback is named
  to the plugin outright.

## 0.63.4

- The pill behind back and forward hugs them, 72 wide: each step is 36
  across (44 high), its glyph 4 toward the other, still 28 apart (Özlem
  2026-10-27).

## 0.63.3

- Back and forward 28 apart: each glyph sits 8 toward the other while
  each step stays 44 to the finger (Özlem 2026-10-27: 36 was still too
  far).

## 0.63.2

- Back and forward 36 apart, as the console draws them: each glyph sits
  4 toward the other while each step stays 44 to the finger (Özlem
  2026-10-27).

## 0.63.1

- Back and forward are drawn in the thin line of start over and close, at
  start over's 20, instead of Material's heavier arrows, in the family
  `theme.style.arrows` names; their pill is 38 high, as the capsule across
  the header is (Özlem 2026-10-27).

## 0.63.0

- Taps are counted on their own: a global pointer route sees each tap
  without joining the gesture arena, and after the frame finds the control
  (Semantics, the nearest button, tab, field or list row), its caption for
  buttons, links and tabs (masked; never a field's text; never a list
  row's text) and a locator. Under 0.2 ms on the route per tap.
- `Rendel.track(name, [props])` sends any event with up to 20 flat
  properties; `Rendel.register` / `Rendel.unregister` set properties for
  the session; `Rendel.setAnalyticsEnabled(false)` stops screen views, taps,
  events, sessions and purchases on the device.
- Sessions: a new one after 30 minutes idle or in the background, and when
  the signed-in person changes. Every item carries it.
- `RendelName`, `RendelMask` and `RendelIgnore` widgets steer what a tap
  records. Rendel's own sheet is never recorded.
- A goal is an event name you mark in the console; the old `goal` kind is
  no longer sent.
- The iOS privacy manifest adds Other Usage Data (linked, not tracking).

## 0.62.2

- Back and forward are 24-point arrows in a 40-point pill again, as before
  0.61.0 (were 20 in 38).

## 0.62.1

- The iOS privacy manifest declares everything the SDK sends: Other User
  Content and Customer Support (the conversation and form values), Photos
  or Videos (an attached photo), User ID (`identify`), Device ID (the
  install id and the push token), Product Interaction and Purchase
  History. All linked to the user, none used for tracking. No audio: speech
  is recognised by the phone's own recogniser. Check your App Store privacy
  answers.

## 0.62.0

- `Rendel.navigatorObserver`: add it to `MaterialApp.navigatorObservers`,
  `CupertinoApp.navigatorObservers` or GoRouter's `observers:` and each
  page the app shows is counted by its route name (ids in a path become
  `:id`), on every device, whether or not Rendel is opened. Views are sent
  in batches every 15 s and when the app goes to the background.
- `Rendel.setScreen(name)` names the current page yourself; the name stays
  with that page. Each turn sends the current screen as
  `context.current_screen`.
- `Rendel.track(name, [props])`: any name other than `purchase` is a goal,
  with an optional `value` and `currency`. `props` is optional now.
- The iOS privacy manifest declares Product Interaction and Purchase
  History, linked to the user, not used for tracking. Check your App Store
  privacy answers.
- New log codes `invalid_goal` and `invalid_screen`; `unknown_event` is gone.

## 0.61.1

- The message box is written at the theme's body size (`type.body`), as
  the web's is, instead of the thread's heading size: the size an app's own
  fields use. Its family is unchanged: the console's `fontFamily`, else
  `RendelConfig.fontFamily`, else the host theme's.

## 0.61.0

- The header's Voice replies, start over and close sit in one glass capsule,
  a hairline between each. Voice replies is always the switch with a speaker
  on its knob; its word is its semantic label, no longer drawn beside it, and
  the header no longer measures whether it fits.
- Back and forward are 20 points in a 38-point pill (were 24 in 40); reset
  and close are drawn in `onSurface` instead of the soft and faint greys.
- The assistant's name is the heading at weight 500, and the header has 24
  points above it (was 16).

## 0.60.3

- Nothing is drawn around the microphone: no ring of the composer's ground
  and no drop shadow, at rest or held.
- The header's reset and close are drawn in a thin line, 20 and 22 points,
  as the console's Appearance phone shows them, instead of Material's
  heavier rounded glyphs at the display size.

## 0.60.2

- The held microphone swells once. When the recogniser opened and
  "Listening…" appeared, the pill was rebuilt and its swell played again, so
  its ring flashed a second time under the finger.

## 0.60.1

- Voice mode looks as Monogram's does, measured from its recording frame by
  frame. Pressed, the microphone's ring goes as the pill swells a fifth into
  its room, in its own colour, with no fade. The page greys a fifth darker
  (in 0.60.0 the veil was not drawn at all). The sphere is 1.7 times the
  screen's width, translucent, a little brighter toward its edge and soft
  over its last twenty points; its crown is at 55% of the screen a third of
  a second after the press and 47% by the end of the first second. Let go
  with words, it swells once while the pill thinks and fades where it is as
  the question is sent; with none, it falls away.

## 0.60.0

- The microphone is held to speak, as on Monogram. Pressed, the "+" and the
  keyboard step aside, the microphone grows and greys, the page dims and a
  frosted sphere rises from under the microphone, blurring what it covers;
  the words are written over it as they are heard. Let go, the question is
  sent: the pill says "Thinking…" while the sphere falls away. A tap sends
  nothing and says to hold the microphone (`RendelStrings.holdToSpeak`, new,
  in all six languages). A screen reader, which cannot hold, still opens
  voice mode with a tap and sends with the pill.
- The built-in recogniser no longer ends after three seconds of silence: a
  pause while the microphone is held does not send half a question.
  `onStopDictating` is what letting go calls; a host's recogniser without it
  ends by itself, as before.

## 0.59.9

- The voice is clean. It came through with loud static on a real iPhone: a
  piece of the voice cut from a longer one reached the speaker with the bytes
  after it, so one byte was played twice and every sample after it was heard
  a byte out. Each piece now goes to the speaker as exactly its own bytes.
- Every answer is read aloud by itself as its opening is written, however
  the question was asked. The Listen button under the answer's first
  paragraph is gone. The header's Voice replies switch still turns reading
  off, and starts on again for everyone: its setting is kept under a new
  name, `rendel_read_answers`. `RendelStrings.listen`, `readAloudThis` and
  `stopReading` are no longer shown, and are kept so an app that sets them
  still builds.

## 0.59.8

- Rendel's own colours follow its new brand. A marked phrase on an answer
  page, the best value in a comparison, a chosen option and a person's own
  items in a list sit on the brand's Toprak mixed into the app's ground (18%
  on a light ground, 30% on a dark one) instead of the yellow.
- `RendelTheme.deep()`, and the dark theme derived from Rendel's own light
  palette, act in a lightened Toprak (`#C87E60`, the black label on it at
  6.2:1) instead of the yellow. An app that sets its own accent keeps it.

## 0.59.7

- Every follow-up also waits as a card at the top of the thread when the
  person opens Rendel, whichever channel carried it: up to three from the last
  seven days that they have not opened or put away (`GET /v1/followups/inbox`).
- `Rendel.followupCards` lists those cards for an app that draws its own;
  `openFollowup(context, id: …)` and `dismissFollowup(id)` act on one.
- An "In the app" message shows as a banner across the top of the screen when
  the send chose Banner, and as the popup over `RendelLauncher` otherwise.
- `RendelFollowup` carries `channel` and `style`.

## 0.59.6

- A long assistant name is set as small as 65% of the heading, not 70%, before
  it is cut or the Voice replies switch gives up its word.
- The header measures the name and the switch's word in the app's own font,
  as they are drawn.

## 0.59.5

- The Voice replies switch keeps its word beside a long assistant name: the
  name is set smaller first, down to 70%, and the word goes only if it would
  not fit even then.

## 0.59.4

- A long assistant name is set smaller to fit the header instead of being cut.

## 0.59.3

- The name is whole from the first answer: the header compacts as if back and
  forward were already shown, so page one and page two share one header.
- Back and forward take a 44 pt tap.
- Listen reads dates in full ("Monday 12 October", "Pazartesi 12 Ekim") in
  English, Turkish, German, French and Spanish.
- The opening text links an https address, a markdown link or an address
  with a path; your `onOpenUrl` opens it.
- The Turkish `readAloud` string says "siz" and "yanıt". No API changes.

## 0.59.2

- The assistant's name always fits: the header checks its own width, and when
  the name would be cut short the switch drops its word and shows a speaker on
  its knob. Back and forward appear once there is a second page. Start over,
  close and the compact switch take a 44 pt tap.
- The header switch is now "Voice replies", and screen readers hear what it
  does: answers to questions asked out loud play by themselves.
- Ratings, review counts, progress, place cards and charts follow the panel's
  language ("4,6 (1.720)" in Turkish), and the stars' Semantics say the rating
  in that language. Whole numbers are grouped the way the panel's language
  groups them ("6,400" in English, "6.400" in Turkish).
- An answer that ends in a confirmation has a Listen button too: it reads the
  opening, then the card's question.
- Scrolled text no longer shows behind the name; the send button is an
  outlined circle until there is something to send.
- New strings `ratingFrom` and `numberLocale`; `autoRead` and `readAloud` have
  new wording in all six languages. No API changes.

## 0.59.1

- Every answer has a "▶ Listen" button under its first paragraph, before its
  cards. While it reads it shows "■ 0:04", the time heard, and a tap stops it.
  It replaces the speaker at the foot of the answer, and it also shows when
  the phone's own voice reads.
- The header's speaker is now an "Auto-read" switch with a visible on/off
  state. It still only reads answers to questions asked out loud. Below 360pt
  it shows without its word, which stays its accessible name.
- A comparison's pinned titles sit on a solid strip, so no row shows through.
- New strings `listen` and `autoRead` in all six languages; `readAloudThis`
  now contains the button's own word. No API changes.

## 0.59.0

**Voice**

- Someone who asks out loud hears the answer: its opening is read by itself,
  and the speaker in the header mutes that. Every other answer has a speaker
  of its own and is read on a tap.
- The voice streams, so it starts sooner. It waits for half a second of
  sound before the first word, so that word is never cut off. Music or a
  podcast playing in another app is turned down under the voice and comes
  back up after.
- The answer's words arrive at a steady pace, with its cards in step,
  instead of in bursts.
- The console's switch (Settings › Voice) turns the voice off without a
  release, as `RendelConfig.readAloud: false` does in code; either off wins.
- New dependency: `flutter_pcm_sound`. Rebuild the app fully once for the
  new plugin.

**Preference memory**

- Rendel remembers what a person tells it once, such as "always
  lactose-free", and says so under the answer, with Undo. Updated and
  forgotten preferences, and an answer based on one, are shown there too.
- A card value or form field filled in from a preference says "From your
  preferences".
- "What I remember for you" lists each preference with Forget, and Forget
  all. `Rendel.openMemory(context)` opens it from your own settings or
  privacy screen.
- 22 new `memory*` strings in `RendelStrings`, in all six languages.

**Follow-ups and push**

- When something a person asked for has news, Rendel shows it over
  `RendelLauncher` and at the top of the thread; a tap opens the
  conversation about it. The SDK asks after `init` and whenever the app
  comes back to the front, at most every ten minutes.
- An app with its own launcher reads `Rendel.followup` and calls
  `Rendel.openFollowup(context)` and `Rendel.dismissFollowup()`.
  `Rendel.isOpen` says whether the thread is on screen.
- `Rendel.setPushToken(token)` and `Rendel.handlePush(context, data)` bring
  follow-ups to the lock screen. The new `rendel_push` 0.1.0 package wires
  both to Firebase Cloud Messaging for you.
- `Rendel.track('purchase', {...})` counts a purchase towards the follow-up
  the person last opened.

No change needed beyond the new version and a full rebuild.
`RendelLauncher`'s constructor is unchanged.

## 0.58.6

**Fixed**

- Answers are read aloud on a test key again, with the speaker in the header.
  0.58.4 silenced test keys, so an app run from Xcode or `flutter run` on its
  test key never spoke; the request it was meant to answer was about other
  sources of sound. No change needed.

## 0.58.5

**Changed**

- The voice starts with the answer's first sentence instead of waiting for
  both: the API makes each sentence's voice separately and at once, and the
  SDK plays the first as soon as it lands and the next after it. In 0.58.3
  the opening was asked for as it was written, but its voice, made whole,
  was still landing after the cards. No change needed.

## 0.58.4

**Changed**

- Answers were not read aloud on a test key (`rd_pk_test_…`), and the
  speaker was not drawn there. Undone in 0.58.6. The SDK declares
  `read_aloud` to the API only when it will read, so no voice is made for a
  thread that would not play it; that part stays. No change needed.

## 0.58.3

**Changed**

- The answer's opening is read aloud the moment it is written, while the
  cards under it are still arriving, rather than once the whole answer has
  finished. The API sends a `speech` event for it and begins the voice then;
  an older API is read at the end as before. No change needed.

## 0.58.2

**Fixed**

- The voice speaks only while the app is in front: an answer that lands with
  the app in the background is not read, and putting the app away stops the
  voice. No change needed.

## 0.58.1

**Fixed**

- The natural voice was never heard on a real iPhone: it was played straight
  from the API's stream, which the device's player refuses without a length
  and byte ranges (the simulator does not ask). The voice is now downloaded
  whole and played from a temporary file, in one request. The API answers in
  byte ranges too, so 0.58.0 is heard as well. No change needed.

## 0.58.0

**Changed**

- Answers are read aloud in a natural voice (OpenAI's "nova"), streamed from
  the Rendel API, in place of the phone's own speech engine, which sounded
  robotic. The phone's voice is still used when the server sends no voice for
  an answer or it cannot be played. New dependency: `audioplayers`. Nothing to
  change in your app beyond a full rebuild for the new plugin.

## 0.57.1

**Fixed**

- On a real iPhone the answer was not read aloud while the ring/silent switch
  was on, which is most of the time: the voice played in the ambient category,
  which that switch silences (the simulator has no switch). It now plays as
  spoken audio, ducking other sound under it, and sets that again for every
  answer because the microphone puts back the category it found. No change
  needed.

## 0.57.0

**Added**

- Each finished answer's opening is read aloud, in the language the answer is
  written in, by the phone's own speech engine in a woman's voice where the
  phone names one (`flutter_tts`, a new dependency). A speaker in the thread's
  header turns it off, and the choice is kept between launches. Nothing to
  change in your app.

## 0.56.3

**Fixed**

- The built-in microphone listens in `RendelConfig.locale`, or the phone's
  language when that is null, and no longer only in `languages`. A recogniser
  hears one language, and an app with `languages: ['tr']` turned a Russian
  speaker into Turkish words; the assistant now answers in the language of what
  it heard. `languages` still picks the answer's language when a message does
  not say. No change needed.

## 0.56.2

**Fixed**

- The message box no longer takes the host app's filled text fields. An app
  whose theme sets `inputDecorationTheme` with `filled: true` saw its fill
  colour as a white plate inside the glass composer; the box's field, and the
  borderless fields on cards, now ask for no fill whatever the theme says.
  No change needed.

## 0.56.1

**Fixed**

- The composer follows the keyboard without a stutter. Its distance from the
  bottom is one sum that moves with the keyboard, so a keyboard on its way
  down no longer takes the composer below its rest above the home bar and
  springs it back up. The page is no longer built again on every frame the
  keyboard moves (only its padding follows), and the composer's blur no
  longer reaches down behind the keyboard. No change needed.

## 0.56.0

**Changed**

- The soft lights behind a question are the app's own colours: its accent,
  its composer where that has a hue of its own, and the accent's neighbours,
  each lifted to a pastel. A black, white or grey brand keeps the yellow,
  lavender and peach. Each question also lays the lights out afresh, so the
  accent's light rises from a different place each time and drifts a way of
  its own. No change needed.

## 0.55.0

**Added**

- A product shows its picture on more cards: `key_value` rows about one
  product draw it beside the title (`image_url`), a `receipt` line that is a
  product draws it before the label (`lines[].image_url`), and an
  `order_tracker` draws up to four pictures of what the order holds
  (`images`) between its head and its steps. The server keeps only a picture
  one of the app's own actions returned. No change needed.

## 0.54.1

**Fixed**

- Voice mode's glow follows the theme. It was near-white on every ground, so
  on a dark theme the words being heard all but vanished; it is now the
  ground lifted a little, and the words read on it at 4.5:1 at least.
- A spoken question is written once. The words heard go the moment it is
  sent, in the place the question is then written, and the pill takes the
  microphone's place without a fade. No change needed.

## 0.54.0

**Added**

- `info_card` draws the picture of the product or item it is about
  (`image_url`) in the icon's place: "Added to your cart" now shows which
  product. The server keeps only a picture one of the app's own actions
  returned. No change needed.

## 0.53.0

**Added**

- A confirmation card shows the picture of the product it acts on, beside its
  question, when the server sends one (`image_url` on `confirm_card`): "Add to
  cart?" now shows which product. The server sends only a picture one of the
  app's own actions returned. No change needed.

## 0.52.1

**Changed**

- The page's plain ground is `surface` (the console's Background), not
  `surfaceRaised`: the console's Appearance phone draws it so, and the phone
  now matches it. Cards stay on `surfaceRaised`. A published backdrop still
  wins.
- The assistant's name in the header is `theme.text.heading`, as the
  console's phone and the web SDK set it, instead of an overline.

An SVG logo now reaches the header too: the API serves it as a PNG, since
`Image.network` draws no SVG. No change needed.

## 0.52.0

**Added**

- `RendelBackdrop` and `RendelTheme.backdrop`: the page's ground as the app's
  own gradient (two to four colours, a direction, optional stops), published
  from the console as `theme.backdrop` and drawn under the thread, its fades
  and the wash a question is asked over, whose lights take the gradient's
  colours. The ink, its quiet steps and the accent's words are solved on the
  backdrop's colours as on the surfaces; a published backdrop no ink can be
  read on is dropped and the page keeps its plain ground. A light theme's
  backdrop is never used in the dark one.
- `RendelArrowStyle` and `RendelStyle.arrows`: the page's back and forward
  steps as chevrons (default), arrows or the iOS chevron, published as
  `theme.style.arrows`.

No change needed: without either, everything draws as before.

## 0.51.0

**Changed**

- Context providers and device reads run side by side, up to four at once,
  instead of one after another. Each provider keeps its 300 ms budget and each
  handler its own `timeout`; `app_state` keeps the providers' order and the
  results keep the order the server asked in, each under its own invocation.
  A turn that reads twice now waits for the slower read, not for both added up.
  The server can put an app back to one at a time without a release
  (`parallel_reads: false` on the app config); `RendelRemoteConfig.parallelReads`
  says which is in force.

**Fixed**

- A handler that returns more than 16,384 characters of JSON is reported as a
  failed action (`result was … bytes, over the 16384 byte limit`, logged as
  `result_too_large`), as the web SDK does. The server refuses a turn carrying
  a larger result, so one big list used to end the whole turn.

## 0.50.2

**Added**

- `RendelConfig.fontFamily` and `RendelConfig.displayFontFamily`: the family
  Rendel is set in, for an app whose font is fetched at runtime rather
  than bundled. `google_fonts` registers each family as `Family_variant`
  (`BaiJamjuree_regular`), so the plain name resolves to nothing and Flutter
  falls back to the system face without saying so; your own font object knows
  the registered name — `RendelConfig(fontFamily: GoogleFonts.baiJamjuree().fontFamily)`.
  Only the typeface: colours and corners stay in the console, and a family
  published there wins over this one.
- `RendelTheme.withFont(family, display: …)`: the same theme in another
  family, which is how the config's reaches the base theme.

## 0.50.1

**Fixed**

- A card with no picture draws the empty plate alone. It used to draw the same
  torn-image icon as a picture that failed to load, so an image the server had
  taken off the block (an address outside the app's own action results and
  allowed domains) was indistinguishable on screen from a broken one. The torn
  icon now means the picture was there and did not arrive.

## 0.50.0

**Added**

- `RendelAction.typeToConfirm`: a parameter the user types back before the
  confirm button arms. The typed value goes to the confirm endpoint, and a
  `typed_mismatch` reopens the card with the reason.
- `RendelAction.fullText` (`RendelFullText(param, current: …)`): a string
  parameter the card shows whole, with a 400-character preview and "Read
  all"; the button arms once it was read. With `current: true`,
  `Rendel.setCardSource(action, (params) async => …)` supplies the text it
  replaces and the card shows the lines that change.
- `RendelAction.confirmLabel` and `confirmLabels`: the confirm button's words.
- `title` and `titles` on `RendelSchema.string`, `number`, `integer`,
  `boolean`, `enumOf` and `list`: the parameter's name on the card, per
  language.
- The card's "Suggested after reading …" line, for a card drawn after
  reading what a customer or a third party wrote, and `RendelStrings` for all
  of the above.
- Uploads send the file's name (`X-Rendel-Filename`).

## 0.49.3

**Added**

- `Rendel.minimised`, a `ValueListenable<bool>`: true while the thread is
  shrunk into its bubble for a screen it opened. A host with its own button
  hides it while this is true, so one way in is on screen.

**Changed**

- `RendelLauncher` hides itself while the bubble is up.

## 0.49.2

**Changed**

- Turkish strings: `helpful` is "Faydalı mı?" (it was empty, so the thumbs
  stood alone), `goBack` is "Geri" (was "Vazgeç") and `irreversible` is
  "Bu işlem geri alınamaz" (was "Bu geri alınamaz"). `confirm` stays
  "Onayla".

## 0.49.1

**Changed**

- A `model_busy` error that arrives before anything was drawn is retried
  once by the SDK itself, after 3 s plus up to 2 s of jitter, with the same
  turn id. Only a second `model_busy` shows the error and Retry; other
  errors are never retried on their own. `ConversationController.autoRetryDelay`
  sets the wait (3 s by default).

## 0.49.0

**Added**

- "Helpful?" with a thumb up and down at the foot of each finished answer
  page, sent to `POST /v1/feedback`. Off unless the published config says
  `copilot.feedback: true` (Appearance › Message box) or `RendelConfig`
  sets `feedback: true`. One tap per answer; the line becomes the thanks.
- `RendelStrings.helpful`, the question beside the thumbs, in every
  language the package carries.
- Analytics events, fire and forget: `assistant_open` when `Rendel.open`
  presents the thread, and `contact_open` with the kind of channel
  (`call`, `email`, `url`) when a contact block's button is tapped, never
  its value. `RendelDispatcher.onContactOpen` carries the tap.

**Changed**

- A config fetch that cannot reach the API (a thrown error, a timeout, a
  5xx) now hides the launcher and sets `Rendel.available` false, with a
  recheck every minute until the API answers again. The config request
  times out at 8 seconds.

## 0.48.0

**Added**

- `Rendel.available`, a `ValueListenable<bool>`: false while the
  organization's usage is paused (credit spent, budget reached, a daily
  ceiling). The launcher hides itself; an app with its own entry point
  listens here. Read from `available` on the published config, re-read every
  five minutes and on resume while false.
- A `paused` notice no longer draws anything: the question is dropped, an
  open sheet closes, and the launcher hides. Open conversations finish.
- `ConversationController.hint` and a quiet line over the composer when one
  question is left under the app's usage limit (`turn.end.remaining`).

## 0.47.0

**Added**

- `notices` capability and the `notice` event: when the assistant will not
  answer on purpose (a person's usage limit, the app's budget or credit
  paused), the thread draws the notice where the answer goes, a quiet plate
  with a clock, the sentence and the app's own link when it set one, and the
  composer rests with the server's short reason ("Back tomorrow") until the
  notice lapses. `ConversationController.notice` and `resting` say so; `send`
  returns false while it rests. Never the error bar or a retry.

## 0.46.6

**Changed**

- The default `assistantName` (and the thread screen's default title) is
  `Rendel`, not `Copilot`. A name from the console or from `RendelConfig`
  still wins.
- The spoken labels and the stalled-answer message say "the assistant" in
  every language: `openCopilot`, `closeCopilot` and `copilotStalled` keep
  their names, only their text changed. The SDK's log messages say Rendel.

## 0.46.5

**Added**

- A screen opened from an answer is reported to `POST /v1/events` as a
  `screen_open` (the answer's id, the card's id and the route's name), so the
  console's Screens page can count opens against how often each screen was
  offered. Only after the route's `open` returns; never for a route that
  threw or is not registered. No change in your code.

## 0.46.4

**Added**

- `RendelAction.editable`: parameters the user may change on the
  confirmation card before confirming. The card draws a control that fits
  each (stepper, number or text field, choice, switch), sends a change to
  `POST /v1/invocations/:id/edit` after a short pause and shows the card the
  server redraws; Confirm waits while a change is on its way or was refused.
  The handler runs with the values the user confirmed.
- New strings in six languages: `cardEditInvalid`, `cardEditFailed`,
  `cardLess`, `cardMore`.

**Changed**

- An answer page keeps its question as one faint line over the answer, cut
  short when long, with a small square of the photo when one was sent.

## 0.46.3

**Changed**

- Only the first paragraph of an opening answer is the lede; the rest of
  that text reads at the body size under it.
- A map leaves room at its sides for the widest pin label, which is
  centred on its point, so a pin near the edge keeps its name.
- A product's name gets three lines.
- A slot sent with `available: false` is shown struck through and cannot
  be picked; a day the slots' title already names is not said again.
- A long pass value (a card number) takes a row of its own.
- A comparison that marks a best value says what the mark means. New
  string: `comparisonBest`.
- A tap on a bar of a bar chart reads that bar out; a second tap goes back
  to the latest.

## 0.46.2

**Added**

- `RendelAction.undoable`: a destructive action the user can still take
  back (an order that can be cancelled while it is packed). Its card does not
  say "This cannot be undone" and its confirm button is not a danger control.
  Sent in the manifest only when set, so existing manifests keep their hash.
- `RendelDictationDenied`: thrown by the built-in recogniser when the
  microphone or speech recognition is refused; a host's own `onDictate` may
  throw it too. The thread then says where to allow it, with Open Settings
  on iOS. New strings: `dictationDenied`, `openSettings`.

**Changed**

- The confirm button reads the card's `confirm_label` from the server
  ("Place order · A$8.41") and stacks above Go back when it is long. An
  irreversible destructive card's confirm is filled in danger, as on the web.
  A long detail value reads whole under its label.
- Voice mode opens when the recogniser starts listening, not behind the
  system's permission prompt.
- Charts write a dollar, pound, yen, rupee or won sign before the amount
  (A$119.04); A$ and US$ count as money for the cents rule.

**Fixed**

- A product card's stars and review count no longer overflow a narrow card.
- A progress ring's value shrinks to fit instead of ending in "...".
- An info card whose meta and body are the same line draws it once; a
  screen card leaves out the route's title when the item already says it.

## 0.46.1

**Changed**

- The opening screen has no mark: the greeting opens it, and the suggestions
  are one card with a hairline between each, not a row of chips.
- The header keeps only its controls until there is a conversation; then it
  shows the name, after the customer's logo when one is published.
- A reset arrow in the header starts a new conversation. It is drawn only once
  there is a conversation, and not while a turn is running.

## 0.46.0

**Changed**

- A form draws no control of the platform's own, as the web SDK does since
  0.23.0. A `date` opens the SDK's month in the field's row (the week
  starting where the host's locale starts it, Monday where nothing says;
  today ringed; days outside `min_date`/`max_date` drawn but not to be
  picked; the month buttons stopping at the bounds), a `time` a list of the
  day's quarter hours on the locale's 12- or 24-hour clock (a prefilled time
  off the quarter listed in its place, an empty one opening at the next
  quarter), and a `date_range` two buttons, From and To, each opening a
  month: picking From goes on to To, and clears To when it is now earlier.
  Days and times are shown in the host's language and still sent as
  YYYY-MM-DD and HH:MM (`{name}_start` / `{name}_end` for a range).
- A `select` opens its options in its row instead of a bottom sheet, with a
  search field only when it is `searchable` or has more than twelve.
- A `toggle` is the SDK's own switch, a track in the accent with a white
  knob, flipped by the whole row and still announced as toggled.
- The pickers, options and days take keyboard focus: Enter or Space picks,
  the arrows move between days, Escape closes, and closing hands focus back
  to the field.
- `Rendel.open` presents the assistant as a page sheet: 8pt under the top safe
  area, its top corners rounded and the app behind dimmed by a quarter.
  `RendelRadiusScale.hero` is 24 (was 28).
- Progress rings draw their arc in the accent (`accentEdge`), not the ink.

**Fixed**

- The action lit beside the microphone reads whole at 360pt ("Add to
  basket", "Track my order"): the microphone narrows to a circle beside it.
  Before, labels past about nine letters were cut off.
- A bar chart keeps one count of decimals across its values, money with
  cents always two ("53.40 €", not "53.4"; 48.25 is no longer "48.3"), and
  says "Today", not "in Today", before a label that is itself a when
  (`RendelStrings.readoutNow` / `readoutNowPeak`). New strings in all six
  languages: `previousMonth`, `nextMonth`, `readoutNow`, `readoutNowPeak`.

## 0.45.2

**Changed**

- `app_not_live` (a live key before the app has gone live) is reported once
  at `warning` instead of `debug`, still as one line and with nothing shown
  to the user, so a log sink that drops debug records still says why the
  launcher is hidden.

## 0.45.1

**Fixed**

- Routes and actions registered one after another right after \`init\` are
  sent as one manifest, one request at a time, the last one always the
  newest. Before, each registration sent its own request with what was
  registered so far, the server kept whichever arrived last, and a build
  could land with a screen missing.

## 0.45.0

**Changed**

- The assistant follows the device's dark mode. On a phone set to dark it is
  drawn in a dark theme: `RendelTheme.deep()` for the default theme, and
  for a theme of your own one derived from it (`RendelTheme.darkFrom`) — a
  dark ground, your accent kept wherever it still reads on one, your sizes
  and faces. An app that is always light should pass
  `RendelConfig(themeMode: RendelThemeMode.light)` to keep the old look.
- The manifest is sent at `init` even when no actions and no routes are
  registered, so the console can tell an installed SDK with no screens yet
  from one that is not installed.

**Added**

- `RendelConfig.themeMode` (`system`, the default; `light`; `dark`) and
  `Rendel.setThemeMode` for an app with an appearance switch of its own.
- `Rendel.init(darkTheme: …)` to choose the dark theme yourself.
- `themeDark` in the published config: the console's dark theme, partial,
  with what it leaves out derived from the published light palette.
- `Rendel.themeOf(context)` and `Rendel.themeFor(brightness)`;
  `Rendel.theme` is now the theme for the device's current setting.
- The config request sends `X-Rendel-SDK` (`flutter/<version>`) and
  `X-Rendel-Platform` (`ios`, `android`, `macos`, …), so the console can
  show which build connected from where.
- When the server answers the config request with `403 app_not_live` (a
  live key before the app has gone live) or `app_suspended`, the launcher is
  hidden, `open()` does nothing, and one debug line is logged with the code
  `app_not_live` or `app_suspended`; the user sees no error. The launcher
  comes back on the next answer once the app is live.

## 0.44.1

**Fixed**

- `RendelStrings.copyWith` kept 15 of its words and returned the rest in
  English, so `RendelStrings.forLocale('tr').copyWith(confirm: …)` lost the
  Turkish set. It now takes and keeps every word.
- `RendelUploadFailure` is exported from `package:rendel/rendel.dart`; it
  was reachable only through `src/`.
- `RendelConfig.onLog`'s list of codes now names every code the SDK logs.

## 0.44.0

**Added**

- `code`: code, a command or log lines on a dark plate, with a copy button.
- `product_cards` chips; `variant_picker` colour swatches and picture
  thumbnails; pros and cons in `key_points`; captions and video links in
  `media_gallery`; notes and changes on `receipt` lines; `progress` rings;
  `chart` area, horizontal-bar and stacked-bar kinds.

## 0.43.0

**Breaking**

- The package now needs Flutter 3.29 and Dart 3.7 or later, because it
  depends on `maplibre_gl` (0.27.x), which installs on nothing older. On
  Android, builds need JDK 21 and may need `ndkVersion` set to the one
  `maplibre_gl` names; see the README.

**Added**

- `place_card`: a place to go to, with open now, today's hours, a call and
  directions built from its coordinates for Apple or Google Maps.
- `map`: places on a map, drawn with MapLibre over open OpenStreetMap data
  served by OpenFreeMap. On the page it is still and scrolls with
  the page; a tap opens it full screen with pan, zoom and Open in Maps.
- `pass`: a ticket, boarding pass, pickup code, coupon or membership card.
  Its QR, Code 128, PDF417 or Aztec code is drawn by the server and painted
  module-exact; Apple's own Add to Apple Wallet button on iOS, Save to Google
  Wallet elsewhere.
- `open_url` with `external: true` (maps links only) opens in the operating
  system rather than an in-app browser.

## 0.42.0

**Added**

- `contact`: how to reach a person at your company, with only the channels
  you list under **Settings → Contact channels** in the console (phone,
  email, a help page). The assistant never hands over or promises a person.
- `rating`: your app's own question about how something went (five stars, a
  thumb or 0–10), answered with a tap and recorded through `POST
  /v1/ratings` with no model turn; asked at most once in a conversation.
- `disclosure`, `checklist` and `timeline`: folded detail, steps the user
  ticks off, and planned things in time order.
- Form bound messages now read as the web SDK's do (`fieldAtLeast`,
  `fieldAtMost`, `fieldOnOrAfter`, `fieldOnOrBefore`), and Send also checks
  date bounds.

**Breaking**

- `EmailAction` joins `UIAction` (the contact card's email channel): a
  `switch` over it with no default case needs a case for it.
- `RendelStrings.fieldMin` and `fieldMax` (new in 0.41.0) are now
  `fieldAtLeast` and `fieldAtMost`: rename them where you set them in
  `copyWith` or the constructor.

## 0.41.0

**Added**

- form v2: `multi_select`, `multiline`, `email`, `tel`, `url`, `date_range`
  and `upload` fields; `autofill` hints; number bounds, steps and a − / +
  stepper; date bounds; a search field for long selects. Values may be lists
  (a multi-select's ticks, an upload's ids) and a date range submits
  `{name}_start` and `{name}_end`.
- `RendelDispatcher.onPickFile`, `fileSources` and `onUpload` for a custom
  dispatcher that draws forms.

Upload fields appear only for an app that turned on **Files in forms** in the
console, and the server never shows a form that asks for a password, a code,
a card number, a CVV, an IBAN or an ID.

## 0.40.0

**Added**

- The `comparison` block: two to four things side by side on the same rows,
  the best value marked, the titles pinned while the rows scroll.
- Three actions, each carried out only on a tap: `call` opens the dialler with
  the number filled in, `copy` puts a value on the clipboard ("Copied"),
  `add_to_calendar` opens the device's own event editor (iOS
  `EKEventEditViewController`, Android `ACTION_INSERT`; on iOS before 17 it
  needs `NSCalendarsUsageDescription` in your Info.plist).
- Richer records: `item_list` amounts, dates, statuses, groups, ranks and
  document rows (up to 20, folding past 8); `order_tracker` ETAs that say when
  they were true, step notes and a copyable reference; `key_value` copy,
  masked values, tones and reference ranges; `info_card` people, documents
  and up to three buttons; `stat_group` "as of"; `booking_card` reference,
  status and start.

**Breaking**

- `CallAction`, `CopyAction` and `AddToCalendarAction` join `UIAction`: a
  `switch` over it with no default case needs cases for them.

## 0.39.0

**Added**

- The `choice` block: a question answered by tapping — one pick from chips,
  or one or several from a list with pictures, with an optional row to write
  your own answer in and a way to skip. The pick goes back by id and the
  block folds into its answer.
- `RendelDispatcher.onChoose` for a custom dispatcher.

## 0.38.0

**Added**

- `Rendel.registerRoute(name, title:, description:, params:, open:)`: a
  screen of your app the assistant may open. Routes ride in the manifest beside
  your actions; the server checks every one before an answer offers it, and a
  param marked `RendelRouteParam(..., fromActions: true)` must equal something
  one of your actions returned.
- The `screens` block: cards that open those screens, the first also lit
  beside the microphone. A tap calls your route's `open`, and the assistant
  shrinks into a bubble in the corner that brings the answer back as it was.
  `RendelConfig.bubbleOffset` (default 104) keeps the bubble above your own
  bottom bar.

**Breaking**

- `NavigateAction` joins `UIAction`: a `switch` over it with no default case
  needs a case for it.
- `Rendel.open()` while the assistant is up no longer stacks a second sheet; it
  returns the one there, or restores it from the bubble.

## 0.37.0

**Breaking**

- `variant_picker` options and `datetime_slots` slots no longer carry an
  `action`. A tap sends the choice by id (`selection`), which the server
  checks against the block it drew; nothing to change unless you built these
  blocks yourself, in which case drop `action` from each option.
- `RendelDispatcher` gains an optional `onSelect`. A custom dispatcher that
  leaves it null draws the options as plain content.

**Changed**

- The handshake declares the action kinds the SDK carries out
  (`reply`, `open_url`).
- A tapped option shows as chosen at once, and the question overlay says what
  was picked ("Size: 43").

## 0.36.0

**Breaking**

- The thread is gone. Every answer is a page and every card opens into its
  detail; there is no conversation of bubbles any more. `RendelConfig.answerPages`
  is removed: delete it where you set it.
- `plan_comparison` is gone from the catalog, with its renderer and the
  `RendelSizeScale.planWidth` and `recommendedShadow` values.
- Removed with the thread: `RendelSentFile` and `send(files:)`,
  `runningActionNames`, and the strings `thinking`, `runningAction`,
  `runningNamed`, `runningCount`, `runningOne` and `runningMany`. The status
  pill says what a turn is doing instead.

**Changed**

- The handshake always declares `answer_pages` and `detail_pages`.

## 0.35.0

**Changed**

- A card on an answer page opens into its detail. Tapping a product or a
  list item slides a sheet up over the page: its pictures, name and price at
  once, from the card, then the detail as it arrives (a summary, a few tags,
  one or two things to do, why it fits, the specifics). The first action is
  lit beside the microphone. Closing the sheet, with ✕ or the system back,
  puts the page back exactly as it was; opening the same card again shows it
  without asking. An item whose action is a link still opens the link.
- Two new components, `actions` (one or two buttons) and `tags`, which also
  draw in a thread. `product_cards` items may carry `images`, more pictures
  of the same thing for its detail.
- The handshake declares `detail_pages` in page mode. Strings
  `statusDetail`, `detailAsk` and `closeDetail` in all six languages.

## 0.34.0

**Changed**

- Each answer is a page of its own, by default (`RendelConfig.answerPages`
  is now `true`). The question is written over the screen as it is asked,
  never as a bubble; the screen gives way, and the answer is drawn from the
  top as one page: its opening sentence, its sections, a short verdict where
  one option was picked, and whole questions to go on with at the foot.
  `answerPages: false` keeps the thread exactly as it was.
- Back and forward are back, in a glass pill at the top of the sheet. They
  show the pages this conversation has opened, from memory; asking from an
  earlier page drops the ones after it.
- While a turn runs, the microphone gives way to a pill that says what is
  happening: thinking, checking your app, putting it together. It reads the
  new `turn.status` event; a build before this one skips it.
- Two new components, `section` (a heading for what follows it) and
  `key_points` (icon, title, a line: the reasons behind a pick, or a
  decision guide). `==phrase==` in a text block is drawn as a highlight.
- Strings `statusThinking`, `statusAction`, `statusComposing`,
  `previousPage` and `nextPage` in all six languages.

## 0.33.0

**Changed**

- Requests carry `X-Rendel-Key`, `X-Rendel-Device` and `X-Rendel-User-Token`
  instead of the `X-NC-` names. The server reads both, so nothing changes for
  a build already shipped.
- An `appKey` may start `rd_pk_`, as keys made in the console since the
  rename do, or `nc_pk_`, as the ones made before do. Both are accepted; an
  older build refuses an `rd_pk_` key, so a new key needs this version.
- `example` reads `--dart-define=RENDEL_KEY` and `RENDEL_API` (the `NC_`
  names still work).

## 0.32.0

**Breaking**

- The package is `rendel`, at `sdk/flutter/rendel`. In `pubspec.yaml`,
  rename the dependency and its path and move `ref` to `v0.32.0`:

  ```yaml
  rendel:
    git:
      url: https://github.com/neon-apps/rendel.git
      path: sdk/flutter/rendel
      ref: v0.32.0
  ```

  and change the import to `package:rendel/rendel.dart`.

**Changed**

- Every public name is Rendel's: `NeonCopilot` is `Rendel`, the `NC` types
  are `Rendel` types (`RendelConfig`, `RendelAction`, `RendelStyle`…), and
  `CopilotTheme`, `CopilotLauncher`, `CopilotEvent` and the other `Copilot`
  types are `RendelTheme`, `RendelLauncher`, `RendelEvent`. The two built-in
  themes are `RendelTheme.paper()` and `RendelTheme.deep()`, and the curve is
  `rendelEase`.
- The old names still compile, as deprecated aliases of the new ones, so a
  build moves over with its import alone and the analyzer points at what is
  left. They go at 1.0.
- The native plugin is `RendelPlugin` (Android `ai.rendel.sdk`, iOS pod
  `rendel`). Nothing to change in the host app: Flutter registers it.

## 0.31.0

**Changed**

- The blocks take the v6 soft-glass finish: every plate is the theme's glass,
  grouped rows sit in one white panel with a hairline, and nothing is a grey
  box or a solid black ring. Text contrast is unchanged; only fills, lines and
  shadows are softer.
- `NCStyle.card` defaults to `NCCardStyle.flat`. A plate is the glass alone,
  without the hairline and the long shadow. `raised` and `outlined` are still
  drawn; set `NCStyle(card: NCCardStyle.raised)` to keep the old look.
- A form is one panel of rows, each with a glyph for its kind, the label over
  the value, and "Optional" on the fields that are. The order tracker is a
  line of soft marks with the current step's name in a pill beside the title;
  its bar layout says "Step 2 of 4". A bar chart leads with its latest value
  and labels every bar. A sold-out variant is struck through and named.
- `NCConfig.apiBaseUrl` defaults to `https://api.rendel.ai`. The old address
  keeps answering; a build that sets its own is unaffected.

## 0.30.4

**Changed**

- No arrows in the header on an answer page. An assistant's header is three
  controls wide, and two of them pointing at a history nobody asked for
  crowded the one that closes it. What a question clears is gone from the
  screen; it is still recorded, and the console's Conversations shows the
  whole thread.

## 0.30.3

**Changed**

- The attach menu is the same glass as the box it opens from. It was a plate
  at 94%, so over a page with any colour on it the menu read as a second app
  rather than as the composer opening.
- The glass keeps less of the composer's colour (0.40 → 0.20). At 0.40, over
  a pale ground, it was a white plate: the page stopped at the composer's
  edge instead of passing under it. The blur is what makes it legible, not
  the fill.

## 0.30.2

**Changed**

- No working row on an answer page. A thread needs one at its foot, or the
  list simply sits there; a page is cleared the moment the question is asked,
  so the composer's own working state — at the one place the hand already is
  — says it alone. Two of them read as two things happening.

## 0.30.1

**Fixed**

- `answerPages` survives the published config arriving. `copyWith` rebuilds
  the host's config when the console's config lands, a few hundred
  milliseconds after `init`, and a field it does not carry goes back to its
  default: the build asked for answers as pages and got a thread, with
  nothing on either side to say why.
- The version the SDK reports to the server is the package's own again. 0.30.0
  announced itself as `flutter/0.29.0`.

## 0.30.0

**Added**

- `NCConfig.answerPages` gives each answer a screen of its own instead of a
  place in a thread. A question clears what is on screen and the answer is
  drawn from the top; the answers before it are a step back through the
  arrows in the header rather than a scroll back, and the question itself is
  not drawn — on a screen holding one answer the heading is the answer's own
  first line. Off by default, so a build that upgrades looks the same
  afterwards. Nothing about what is sent or kept changes with it: every turn
  is still written down, and the console shows the whole thread whichever way
  the app drew it.
- Such a build declares `answer_pages`, and the server then closes a
  substantial answer with `quick_replies` carrying a heading, an icon each
  and whole questions, which the SDK draws as cards at the foot of the page.
  To a build that does not, they stay pills in a row, where a sentence does
  not fit.

**Changed**

- `init` refuses an example's placeholder key (`nc_pk_test_...`) the way it
  refuses a key without `nc_pk_`, and both messages say where the app's key
  is: the console's Settings → API keys. A key the server does not know is
  logged as `invalid_key` with the same line, at the first config fetch,
  instead of surfacing later as a network error.

## 0.29.0

**Added**

- `NeonCopilot.pair(code)` pairs a test build with the console. The console
  shows a code like `K7Q2-M9XD`; pass what the developer types into your
  build's own pairing screen, and the console watches this device's
  conversation for the next two hours. It only watches: nothing about the
  assistant changes once paired. Test keys only, and a code works once, for ten
  minutes. It never throws: the `NCPairResult` it returns is `ok` with
  `endsAt`, or carries an `NCPairFailure` reason (`testOnly`, `notFound`,
  `rateLimited`, `failed`) and a sentence the screen can show as it is. Safe
  to call before `init`, which it waits for briefly. Each outcome is logged
  under a stable code: `paired`, `pair_test_only`, `pair_not_found`,
  `pair_rate_limited`, `pair_failed`.
- Blocks replace themselves. The assistant can name something that will change
  (a cart, an order, a set of slots) and draw it again as it changes; the
  new drawing takes the old one's place, where the conversation now is,
  instead of a second cart appearing beside the first. A size or slot the
  person picked stays picked while the new drawing still offers it (unless a
  redrawn picker names its own selection, which already reflects the tap),
  and a field that had the keyboard keeps it. A drawing older than the one on
  screen, which a retry can deliver late, is dropped and logged at debug as
  `surface_stale`. The build declares `surface_update`, and the server only
  lets the model do this for a build that does; forms that update in place
  work as before. `variant_picker` now marks the option the person tapped,
  as `datetime_slots` already did.

## 0.28.0

**Added**

- Forms update in place. When the assistant redraws a form the person has not
  sent yet — "make it a refund to my card" — the new form takes the old
  one's place instead of appearing beside it, and keeps every answer the
  person gave for a field that is still there; a field they changed
  themselves keeps their value whatever the assistant now proposes. If they
  were typing in a field, they carry on typing in the same field of the new
  form. A form that was sent is never replaced. Each message also tells the
  assistant what is in the open forms (up to three), so it answers knowing
  what was already chosen. Nothing to wire: the SDK declares this to the
  server as `form_update`.

## 0.27.0

**Added**

- Confirmation cards for console actions that change something — "book me
  in on Tuesday", "cancel my order" — when the endpoint is set to *the
  signed-in user's token*. The assistant asks the person first, as it does for
  your own write actions; once they confirm, Neon Assistant makes the call
  itself, as them, and answers with what happened. There is no handler to
  register and nothing to wire: it needs only `NCConfig.userToken` (0.26.0).
  Without a token the person is told they are not signed in, and nothing
  changes.

## 0.26.0

**Added**

- `NCConfig.userToken`: the signed-in person's current token from your own
  sign-in. The assistant can then answer from your API as the person asking —
  "my order", "my routine" — with no API key to issue: set those endpoints
  to *the signed-in user's token* in the console. It is asked for before
  every question, so return the current one (your auth library refreshes
  it), or null when nobody is signed in. It goes with the question as the
  `X-NC-User-Token` header and on to your endpoints as
  `Authorization: Bearer`; it is never stored. A function that throws costs
  that one header, not the answer.

## 0.25.1

**Changed**

- The message box is clearer glass: it keeps 40% of your composer colour
  instead of 66%, and the band behind it is lighter, so the lights and the
  thread plainly show through. The light nearest the box is a little
  stronger. Nothing to change in your code.

## 0.25.0

**Changed**

- The conversation's ground carries three soft lights in your accent — its
  own hue and two turned either way round the colour wheel, lifted to
  pastel — and the message box is glass: the lights and the thread show
  through it, blurred, under a thin light edge. The box keeps most of your
  composer colour, so its words keep their contrast. Nothing to change in
  your code. The web SDK (0.3.0) and the console's previews draw the same.

## 0.24.0

**Changed**

- The microphone opens voice mode instead of the message box. The
  conversation goes under a frosted wash in your accent, a glow rises from
  the bottom and swells with the speaker's voice, and the words are written
  in the middle as they are heard. When the speaker stops, the question is
  sent on its own, and the microphone becomes a dark pill saying what the
  assistant is doing until its answer starts. The pill stops listening and
  sends; a tap anywhere else lets the question go unsent. Nothing to change
  in your code; a recogniser of your own (`NCConfig.onDictate`) gets the
  same voice mode, without the glow following the voice.

## 0.23.0

**Added**

- The composer's "+" opens Photos, Camera and Files. Camera takes a photo
  and attaches it the moment it is taken; Files reaches PDFs, text files and
  pictures through the system's document picker, the SDK's own native code
  rather than another package. Photos and Files need no permission. Camera
  needs `NSCameraUsageDescription` in `ios/Runner/Info.plist` — add it next
  to the microphone's two lines; without it the "+" offers no Camera and
  `usage_description_missing` is logged. Android needs nothing from you.

**Changed**

- The composer is the one the console's phones draw: at rest a round "+",
  the microphone as a filled pill and a round keyboard; the keyboard opens a
  message box two lines tall, with Photos, Camera, Files and send. It floats
  over the thread on a frosted band, and settles back to rest at a tap
  elsewhere when it is empty. `NCConfig.attachIcon` now defaults to
  `NCAttachIcon.plus`.
- `NCConfig.onPickAttachment` stands in for all three sources: the "+"
  opens your picker directly.

**Fixed**

- The message box no longer sits under the keyboard. The sheet never made
  room for it; a simulator with a hardware keyboard never showed it.

## 0.22.0

**Breaking**

- `identify` no longer takes `name`, `email`, `avatarUrl` or `gender`, and
  `NCGender` is gone: 0.21.0 added them for a console page that no longer
  shows them. If you passed them, pass what the assistant should know in
  `traits` instead, for example `traits: {'name': user.name}`.

## 0.21.0

**Added**

- `identify` takes `name`, `email`, `avatarUrl` and `gender` (`NCGender`).
  They are how the person shows on the console's Users page — a photo, or a
  woman's or a man's figure when there is none — and what the assistant may
  call them. All optional, and nothing changes for a call with only
  `userId`. They travel as traits under the names the console reads; an
  email with no `@` or a photo that is not https is left out and logged.
  `traits` stays for anything else, such as a plan.

## 0.20.0

**Fixed**

- A card's link — "Go to the product", a booking's "Open the page" — now
  opens with nothing but `init`. Until now it needed `NCConfig.onOpenUrl`,
  which the quickstart never mentions, so the button was drawn and did
  nothing. The SDK opens it in an in-app browser (`url_launcher`), so closing
  the page brings the user back to the conversation. `onOpenUrl` still
  replaces it, for an app that routes links to its own screens. Nothing to
  add in your code; on Android the SDK's manifest names the browsers it may
  open, which is not a permission.

## 0.19.0

**Added**

- A card's own buttons are parts too, each with its words as a part of its
  own: the info card's `button` and `button_text`, the confirmation's
  `confirm`, `confirm_text`, `cancel` and `cancel_text`. A button part takes
  a `fill` and a `radius`; its words take a colour and a size. Nothing to add
  in your code.
- `NCPartLook(fill:, radius:)`, and `NCActionButton(part:)` for a button
  drawn as a card part.

## 0.18.0

**Added**

- The parts inside a kind of card can each have their own colour and size:
  `theme.cards.<kind>.parts` in the published config. Product cards: badge,
  title, subtitle, stars, reviews, price. Info card: title, body. List:
  title, subtitle, trailing. Order tracker: title, step, time. Confirmation:
  summary, details, warning. A part's colour, like every colour, only comes
  with a published palette. Nothing to add in your code.
- `NCCardLook(parts: {...})` with `NCPartLook` sets the same in code, and
  `CopilotTheme.part(name, style)` is how a renderer dresses one.

## 0.17.0

**Added**

- One kind of card can look different from the rest: `theme.cards` in the
  published config, keyed by block type (`product_cards`, `info_card`,
  `item_list`, `order_tracker`, `confirm_card`). Each may set its own plate
  colour, picture well, corner and build (shadow, outline or flat); anything
  it leaves out is the theme's. Nothing to add in your code.
- `CopilotTheme(cards: {...})` with `NCCardLook` sets the same in code, and
  `CopilotTheme.forCard(type)` is the theme a block of that type is drawn in.

## 0.16.0

**Added**

- The look a console publishes can change how the parts are built, not only
  their colours: `theme.style` in the published config. Nothing to add in
  your code; it arrives with the rest of the theme.
  - Plates and cards: a shadow (as before), an outline, or flat.
  - Buttons inside blocks: filled (as before) or outlined. The launcher and
    the send button keep their look.
  - `product_cards`: tiles across (as before), a list with the picture at the
    side, or full-width photographs.
  - `order_tracker`: steps down (as before), steps across, or one progress
    bar with the current step under it.
- `CopilotTheme(style: NCStyle(...))` sets the same in code; a published
  style overrides it key by key.

## 0.15.0

**Changed**

- Three of the four platform lines a host used to add are gone.
  - The paperclip needs no permission: the picker is asked for the image
    without its library metadata, which is what made iOS ask for the photo
    library. `NSPhotoLibraryUsageDescription` is no longer needed.
  - Android needs nothing: the SDK's own manifest declares `RECORD_AUDIO`,
    and `INTERNET`, which Flutter's template grants only to debug builds.
    The build merges both into the app.
  - iOS still needs `NSMicrophoneUsageDescription` and
    `NSSpeechRecognitionUsageDescription` for the microphone — Apple shows
    them in the app's name, and no package can write them. Without them the
    SDK no longer lets iOS close the app on the first press: the microphone
    is not drawn, and `usage_description_missing` says which line is absent.
- `neon_copilot` is a Flutter plugin now, for those two things: an Android
  manifest and a small iOS check of `Info.plist`. Swift Package Manager and
  CocoaPods both build it. Rebuild after upgrading; a hot restart does not
  load native code.

## 0.14.0

**Changed**

- The signed-in user survives a relaunch. 0.13 held it in memory, so every
  host had to call `identify` again in its session-restore path — code the
  quickstart does not show — or the relaunched app talked as nobody. Now
  `identify` once at sign-in and `reset()` at sign-out are the whole
  integration; the user is kept in the same device storage as the device id,
  and `reset()` removes it. Calling `identify` on every launch still works.
- `resetForTest` takes `relaunch: true`, which keeps the stored user the way
  a cold start does. It also no longer carries the thread of a test that
  ended with the sheet up into the next one.

## 0.13.0

**Breaking**

- The signed-in user rides on every turn instead of being kept by the server
  for the phone. That binding outlived the logout: after `reset()` the next
  person on the same phone talked into the last one's history. Now
  `identify` holds the user in memory and every turn carries it, `reset()`
  clears it, and a turn with nobody signed in is anonymous.

  The edit it asks of you: call `identify` on every launch that restores a
  session, not only at sign-in. The quickstart has said so since step 4 was
  written; until now the server's binding covered for an app that did not.

**Changed**

- `identify` before `init` is kept and sent once the assistant starts. It used
  to be dropped without a word.
- `identify` with a different user than the one signed in clears the thread
  on screen, so a host that forgot `reset()` at the logout does not hand one
  person's conversation to the next.
- `identify` no longer throws when the network fails. It reports
  `transport_failed` through `onLog`; the turns carry the user either way.

**Fixed**

- `reset()` with the sheet up threw a `RangeError` from the thread list as it
  swapped to the empty state.

## 0.12.2

**Changed**

- The device id survives a relaunch. It did not: without a
  `NCConfig.deviceIdStore` every cold start minted a new one, so the console's
  Users page showed one "Not signed in" row per launch of the same phone,
  per-device rate limits reset each time, and what the assistant remembered
  about a person was attached to an id that never came back. `shared_preferences`
  is a dependency now, and both stores — the device id and the config cache —
  default to it. `deviceIdStore` and `configStore` still replace them.

  Rows created before this release stay as they are; from this release on,
  one phone is one row. One *person* across phones still takes `identify`.

## 0.12.1

**Fixed**

- The SDK reports its real version. `NCConfig.sdkVersion` defaulted to the
  literal `flutter/0.1.0`, so eleven releases in every app still introduced
  itself as the first one: the console printed it beside the manifest, and a
  minimum-version floor of any height would have refused them all. The
  version now lives in one constant that a test pins to `pubspec.yaml`.

## 0.12.0

**Changed**

- The paperclip and the microphone work the moment the dependency is in.
  `neon_copilot` now depends on `image_picker` and `speech_to_text`, and the
  composer's two controls use them when the host wires nothing.

  The SDK shipped neither, on purpose: no forced plugin, no version conflict,
  the app's own permission prompt. The cost was 150 lines copied into every
  host, carrying every subtlety a microphone has, and the first real
  integration copied them and lost a day to the microphone. An assistant that
  has to be assembled is not the product.

  `NCConfig.onPickAttachment` and `onDictate` still replace the built-ins;
  `NCAttachIcon.off` and `NCVoiceIcon.off` still remove the controls.
  `onStopDictating` is read only alongside a host's own `onDictate`.

  Two things stay with the host, because the platform shows them to its
  users: the iOS usage strings in `Info.plist` (photo library, microphone,
  speech recognition) and `RECORD_AUDIO` on Android. The install page lists
  them; without the iOS ones the app is killed on the first press.

- The example app drops its own picker and recogniser and the two plugins
  behind them. It is now the shape a customer's `main.dart` takes: `init`,
  actions, a launcher.

## 0.11.4

**Changed**

- The rest of the SDK's own words move into `NCStrings`, so an assistant in a
  Turkish app is Turkish to the last label. A form said "Required" beside
  every field and "Sending…" under the answers; a receipt summed to "Total";
  a confirmation card resolved to "Expired" or "Not confirmed"; the header
  wore "Test mode"; a date field prompted "Choose a date"; a day of booking
  slots was headed "Wed 24 Sep"; and every control a screen reader names —
  open, close, message, attach, send, speak, stop, remove — was named in
  English. Thirty-six fields, in the five shipped languages, with the same
  caveat as the rest: written by the engineer, not reviewed copy.

`NeonCopilot.strings` is the set in use, for a host that draws a control of
its own beside the launcher and wants the same words.

## 0.11.3

**Changed**

- The remove control on a file waiting in the composer is a 22pt circle.
  0.10.1 said it was 20pt; it rendered at 44, half the width of the card,
  because `NCPressable` floors every target at 44pt and a decorated box handed
  that floor paints to it. The target keeps its floor. The circle is drawn in
  the middle of it, overhanging the corner as before.

## 0.11.2

**Changed**

- The error bar speaks the app's language, all of it. Its one control read
  'Try again' whatever `NCStrings.retry` said, and the sentences the SDK
  raises itself — a stream that dropped, a turn that ended without an answer,
  a confirmation that expired, a file that could not be attached — were
  English literals in the controller and the thread, drawn under a Turkish
  answer next to a Turkish composer. `streamDropped`, `noAnswer` and
  `confirmationExpired` had been in the catalog since it existed; nothing read
  them. `turnFailed`, `copilotStalled` and `attachFailed` join them.

- The sentences the server puts in that bar arrive in the app's language too.
  "That answer got too long to finish" was the one it was reported on; the
  gate messages, the busy model and the internal error go the same way, chosen
  by the same rule the answer's language is — the device's, narrowed to what
  the app declared. Every request now carries `Accept-Language`, so an
  upload the server refuses is refused in the same language.

`ConversationController.errorCode` names which error `errorText` is: the wire
code for a server's, the SDK's own for the rest. The controller still has no
strings; the words are the thread's.

## 0.11.1

**Changed**

- A dictation that fails is reported as a failure, in the app's language.
  `NCStrings.dictationFailed` is the sentence, and the host's error is logged
  under `dictation_failed`, so the console shows the platform's own code.

  It read "That could not be heard. Try again." — in English, under a Turkish
  thread — and the reason went nowhere. Worse, the example app never threw at
  all: `speech_to_text` on iOS sends `done` before the error, the handler
  closed the dictation on the first `done`, and every recogniser failure
  reached the SDK as silence. The screen said to check the microphone. The
  microphone was fine; the simulator's on-device speech model had been purged
  and the recogniser died within milliseconds of every start,
  `error_unknown (300)`.

- The example app waits one turn of the event loop before it closes a
  dictation, so an error posted behind the ending is the ending. The three
  errors that mean nobody spoke — `error_no_match`, `error_speech_timeout`,
  `error_retry` — still complete as silence.

**Documentation**

- `NCConfig.onDictate` says which ending is which — null for silence, a throw
  for a recogniser that failed — and what a simulator that fails every session
  looks like in its log.

## 0.11.0

**Added**

- A message shows what was sent with it. Pictures appear above the bubble, on
  the side the sender writes from; documents appear as a named card.

  Until now a photograph went up, the composer cleared, and the thread showed
  only the sentence — leaving the sender unsure the file had gone, and the
  answer referring to something they could no longer see.

`NcMessage.user` carries `files` for this, and `ConversationController.send`
takes them. The bytes are the composer's own preview, one step along.

## 0.10.1

**Changed**

- A file appears in the composer the moment it is chosen, wearing a scrim and
  the thread's own breathing dot until the upload lands. The picker used to
  close onto an unchanged screen while the bytes went up, which reads as a
  picker that did nothing.
- The send control is off while an upload is in flight, and a turn refuses to
  carry an attachment that has no id yet — the same fact said twice, because a
  file silently missing from a question is worse than a moment's wait.
- The remove control is smaller: 20pt rather than 24, over a 92pt card.

## 0.10.0

**Changed**

- A file waiting on the composer is drawn as what it is. A picture shows
  itself; a document shows an icon, its name and its size. Both carry a corner
  control, because picking the wrong file is the most likely thing to go wrong
  there.

  It used to be a pill with the filename in it, which read
  `image_picker_33893816-5E2E-495D-BEBB-…` — a photograph is recognised by
  looking at it, and a document by a name and a size the pill had room for
  neither of.

The bytes are kept for the preview after the upload rather than discarded.
They were already in memory when the file was picked, and a picture is the
only honest thumbnail of itself.

## 0.9.4

**Documentation**

- `NCConfig.onDictate` now says the thing that broke a working microphone:
  ask the recogniser which locales the device actually has, and only then
  request one.

  A locale with no model behind it does not degrade — `listen` fails with a
  permanent platform error the instant it starts, so the control opens and
  shuts and looks exactly like a broken microphone. 0.8.2 told hosts to pass
  the assistant's language without saying to check for it first, which turned a
  recogniser that worked in the device's own language into one that did not
  work at all. Simulators usually carry a single language; a phone set up in
  one country carries few.

  The example matches the full tag, then the language, then falls back to the
  device's own.

## 0.9.3

**Documentation**

- `NCConfig.onDictate` gains the third thing a host writing this handler has to
  know: a recogniser asked to listen while the previous session is still
  releasing the audio hardware does not start, does not raise, and does not say
  so. It is why a microphone works for the first few presses and then stops —
  each session leaves a little less room for the next.

  Cancel anything still running, give the platform a moment, and if it is still
  not listening afterwards complete the future rather than leaving a lit
  control attached to nothing. The example app does all three.

## 0.9.2

**Added**

- `NCStrings.nothingHeard`, shown when a dictation ends having captured
  nothing.

  A recogniser that cannot reach a microphone — a simulator with no audio
  input, a device that handed the audio session to something else — reports a
  clean, immediate end rather than an error. The control opened and shut under
  the user's finger and said nothing about why. It says so now, and only when
  the composer is empty too: somebody who stopped a dictation they had already
  filled in does not need telling.

## 0.9.1

**Documentation**

- `NCConfig.onDictate` warns about the ending that arrives before the
  beginning: a recogniser can report `notListening` before `listen` has been
  called, and a handler that treats every such report as the end closes the
  dictation the instant it opens. The example app guards it now and is the
  shape to copy.

Nothing in the SDK itself changed.

## 0.9.0

Dictation you can watch.

**Breaking**

- `NCConfig.onDictate` is handed a callback:

  ```dart
  onDictate: (onPartial) async {
    await speech.listen(onResult: (r) => onPartial(r.recognizedWords));
    return finished.future;
  }
  ```

  Call it with every partial the recogniser produces. Those words go into the
  composer as they are heard — which is the difference between dictation and a
  box that fills in once you have stopped talking. The return value is
  unchanged: the final text, or null.

  The edit is one parameter and one line inside your `onResult`.

**Changed**

- Pressing the microphone clears the composer before it starts listening. It
  used to leave the last transcript there for the new words to land on top of,
  which produced a sentence that was half of one thing and half of another.
  Speaking is a correction as often as it is an addition.

## 0.8.2

**Documentation**

- `NCConfig.onDictate` now says the two things that make a microphone work,
  both of which the example app was getting wrong: complete the future on
  every path a recogniser can end on, and tell it which language to listen
  for. A future that never completes leaves the SDK believing it is still
  listening — the control stays lit and the press that would stop it does
  nothing — and a recogniser left on the device's own locale listens for the
  wrong language and hears nothing.

The example app is fixed on both counts and is the shape to copy.

## 0.8.1

**Fixed**

- The working row said "Thinking" on a thread whose every other word was
  translated. `State.context` sits above whatever `build` returns, so the
  `CopilotStringsScope` created there was invisible to the State's own
  methods: the lookup found nothing and fell back to the English defaults,
  while the empty state — a child widget, under the scope — came out in
  Turkish a few pixels above it.
- The composer's prompt while a turn runs was the literal `Working…`. It is
  `NCStrings.working` now, translated with the rest.

## 0.8.0

**Added**

- `NCConfig.emptyStateTitle`, and the matching field in the console under
  Appearance. The empty thread's headline was the one line on that screen a
  customer could not write — the sentence under it has been theirs for
  releases.

  Null keeps the SDK's own, translated into whichever language the assistant
  answers in. A blank one falls back rather than clearing: unlike the line
  below it, a thread opening on nothing but a subtitle reads as a page that
  failed to load.

## 0.7.1

**Fixed**

- The empty thread's headline and its default subtitle were English literals in
  the widget rather than strings, so an assistant answering in Turkish still
  opened with "Ask anything about this app." — on the one screen where the SDK
  speaks before the user does. They are `NCStrings.emptyTitle` and
  `emptyBody` now, translated with the rest.

  `NCConfig.emptyStateBody` still wins over the second: a customer's own
  sentence beats a translation of ours.

## 0.7.0

One screen, one language.

**Changed**

- The SDK's own words — the empty state, the working row, the confirm buttons,
  the composer prompt — now choose their language the way the answer does:
  through `NCConfig.languages`, with the device deciding among the named ones
  and a device speaking none of them getting the first.

  They used to come straight off the device while the answer went through the
  list, which put a Turkish composer prompt and an English empty state on the
  same thread. Two languages on one screen, and no way for the reader to tell
  which was the mistake.

Nothing changes for an app that names no languages, or one that sets
`NCConfig.strings` itself.

## 0.6.0

The microphone, once it is listening.

**Added**

- `NCConfig.onStopDictating`: ends a dictation when the user presses the
  microphone again.

  ```dart
  onStopDictating: () => speech.stop(),
  ```

  Optional, and what turns the control into a toggle. Without it the microphone
  cannot be pressed mid-session — there is nothing for the press to do — and a
  session ends only when the recogniser decides it has, which on a pause is
  several seconds of somebody looking at a control that will not answer.

**Changed**

- A listening microphone is drawn at full strength in the accent, and breathes.
  It used to be dimmed to the disabled weight, which is the same treatment an
  upload in flight gets and the opposite message: an upload says wait, a live
  recogniser says go on, speak. Nothing moves for a reader who has asked for
  less motion; the colour carries it.

## 0.5.0

The languages an app is willing to be answered in.

**Added**

- `NCConfig.languages`: the languages this build ships strings for and whose
  transcripts its support team can read, in preference order.

  ```dart
  NCConfig(languages: ['tr', 'en', 'ru'])
  ```

  The device still decides which of them is used — a Russian phone gets Russian
  with nothing else configured. A device speaking none of them gets the
  **first**, so the order is a decision and not a detail.

`locale` is unchanged and is a different thing: one device's setting, or the
one language a host with its own picker wants this turn answered in. This is
the set that setting is chosen from.

Empty — the default — hands the choice to the list published from the console
under **Experience → Persona**, and absent that the assistant answers in whatever
it is addressed in, which is what it has always done. Nothing changes for an
app that sets neither.

## 0.4.0

Two things a user can hand the assistant, and one thing the package stopped
carrying on everyone's behalf.

**Added**

- `NCConfig.onPickAttachment`: a file the user attaches, from whatever picker
  this app already has. Return an `NCAttachment` — bytes, name, media type —
  and the SDK uploads it, shows its name on a chip in the composer, and puts it
  in front of the model on that turn. Images, PDFs and plain text, up to 20 MB.
- `NCConfig.onDictate`: speech as text, from whatever recogniser this app
  already has. What comes back lands in the composer rather than being sent, so
  it can be read and corrected first.
- `NCAttachment`, for the first of those.

Both are null by default, and null means the control is not drawn. That is the
same rule `onOpenUrl` has always had, for the same reason: a paperclip that
opens nothing is worse than no paperclip.

**Why they are hooks rather than features**

The package depends on `crypto` and `http`, and it was going to depend on a
file picker and a speech plugin. That would have been a build cost for every
app that will never use either — and a failed `pub get` for the app that
already pins a different major version of one, which cannot then install this
SDK at all. It also meant a second photo-permission prompt in an app that has
its own. So the choosing is the host's and the protocol is ours.

The example app wires both in about thirty lines, and `/docs/install` shows the
shape with `image_picker`.

**Breaking**

- The two thumbs under a finished answer are gone, with `NCStrings.ratedHelpful`
  and `ratedUnhelpful` now unused (kept, because removing them would break a
  host that sets its own strings). Nothing to edit unless you were relying on
  the rating reaching Analytics.
- The pencil in the thread header is gone. `NeonCopilot.reset()` still clears a
  thread, so a host that wants a new-conversation control can draw its own.

**Changed**

- The assistant's own prose is drawn in a bubble, mirroring the user's. Catalog
  components are not: a chart or an order tracker carries its own ground, and a
  bubble around it reads as a panel inside a panel. The bubble derives from
  `surfaceRaised`, so a published palette gets one with no new control in
  Appearance.

## 0.3.0

The message box, which was the one part of the thread a brand could not reach.

Nothing in here changes what an existing theme draws. Every role below falls
back to what the composer already used, and the SDK's own parity tests pin the
unchanged case on both sides of the wire.

**Added**

- `NCColors.composer` and `NCColors.onComposer`: the bar a user types in, and
  the words they type into it. A pair of its own rather than a fifth surface —
  the composer is the one element that stays put while the thread scrolls past
  it, and "a dark bar under a light thread" is a pairing the surface ladder
  cannot express, because the ink is solved across four grounds at once.
  Absent, the box is `surfaceHigh` with `onSurface` on it, which is exactly
  what it has always been.
- `CopilotTheme.onComposerFaint` and `CopilotTheme.composerEdge`: the prompt
  before anything is typed, and the boundary WCAG 1.4.11 asks 3:1 of. Both are
  solved on the box once the box has a colour of its own, and both hand back
  the thread's own answer until then.
- `NCConfig.attachIcon`, `voiceIcon` and `sendIcon`, with `NCAttachIcon`,
  `NCVoiceIcon` and `NCSendIcon`. Publishable from the console, like the
  launcher label beside them. A closed set of names and never an image: an icon
  a device fetches from an address in a published payload is a tracking pixel
  aimed at somebody else's users.
- `off` on the attachment and voice controls. Both are drawn disabled until
  their features land, and an app that is never going to accept a photograph
  should be able to say so rather than show a paperclip that stays grey.
  There is no `off` for send.
- `NCColors.onComposerFaint`: the prompt in the box, as a colour a brand can
  state rather than one derived from the words the user types. A placeholder
  is usually a quieter step of the typed text and sometimes is not, which is
  the distinction a single ink role cannot carry. Stated, it is rescued
  against the box like any other text; absent, it is derived exactly as it was.
- `NCConfig.composerHint`, publishable: the words in the box before anyone has
  typed, for an app that would rather prompt for something specific than for
  anything.

**Fixed**

- The composer drew the literal `'Ask anything'` and ignored
  `NCStrings.composerHint`, which has carried a translated prompt for every
  language this package ships since the strings existed. A Turkish app
  prompted its users in English while every other word on the screen was
  Turkish. Nothing failed — it just read as somebody else's app.

## 0.2.0

Appearance, and one field that can now be trusted to mean what it says.

**Breaking**

- `NCColors` gained `bubble` and `onBubble`, and their defaults are not what
  the thread drew before. A user's message used to take the ink colour with
  the ground for its words; it now takes a step of the ground with the ink for
  its words. An app that wants the near-black bubble back states it:
  `CopilotTheme.fromTokens(..., bubble: <colour>, onBubble: <colour>)`, or
  publishes the pair from the console. Nothing else about a theme moves.
- The surfaces a theme derives — raised, sunk, floating — no longer read the
  ink at all. They were mixed toward it, which meant a change to the TEXT
  colour repainted every plate; on a coloured ground it could invert the whole
  elevation model. A light theme shifts by a unit or two per channel. A dark
  one shifts more, and in the direction it should have been going.

**Added**

- `rating` and `rating_count` on a product card, drawn as five stars clipped
  to the score with the number and the count beside them. A review score used
  to have nowhere to go but the badge, as text the model had to spell.

**Changed**

- The composer is one box: what you are writing, with a row under it carrying
  the send control. An attachment and a microphone sit in that row, disabled
  and labelled as such, because both features are wanted and neither exists.
- A product card no longer crops its picture. A catalogue shot is one object
  photographed whole, and covering a fixed strip cut the top off every bottle
  on the shelf; the picture now sits contained in a tinted well.
- A message and a plate each tighten the corner nearest whoever said it —
  directionally, so a right-to-left thread swaps both sides together.
- A recorded block casts no shadow. The surface step separates it from the
  thread, and a soft drop under every answer in a column of them read as haze.
  A block waiting on an answer still floats: that elevation says there is
  something to deal with before the turn goes on.
- The composer no longer casts its shadow upward onto the blocks it covers.

## 0.1.0

First release. Flutter, iOS and Android.

- `NeonCopilot.init` with a publishable key, `open(context)` for the thread,
  and `CopilotLauncher` for the entry point.
- Twenty-one typed NCUI components, drawn as native widgets from your own
  design tokens. The model chooses from the catalog and cannot invent a
  twenty-second.
- `registerAction` with typed parameters and a risk level. `read` runs on
  request; `write` and `destructive` are proposed, and the platform renders a
  confirmation card built on the server from your own template and the
  parameters it validated.
- Context providers (`addContextProvider`) for live app state, and
  `identify` with optional backend-signed verification.
- Theming through `CopilotTheme.fromTokens`, with a contrast audit that
  refuses a palette it cannot make legible.
- Remote configuration: appearance and opening surface published from the
  console, cached on device, layered over your code config and never under it.
- Recovery built in: a dropped stream settles into a retryable error, a retry
  carries the turn's id so nothing is written or billed twice, and a
  confirmation the network lost is re-served rather than re-proposed.
