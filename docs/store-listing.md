# Store listing

What the Google Play Console asks for, answered from what the code really does. When the app changes
what it sends, keeps or shows, update this page, `site/privacy.html` and `GameState.AI_CONSENT_TEXT`
in the same change ([`rules.md`](rules.md) §2). The Play Console's form wording changes, so re-read
each question when you fill it in. Where an answer below doesn't fit the form, the code wins.

Status: **drafted 2026-11-09, not yet submitted.** The pages in `site/` are not online yet: GitHub
Pages must be turned on once ([`next-steps.md`](next-steps.md) 1.7). The answers below describe the
game **before** Phase 2's required sign-in; [`next-steps.md`](next-steps.md) 2.4 lists what changes
with it.

---

## 1. Public pages (`site/`)

The pages are static HTML with no scripts, fonts or trackers. `.github/workflows/pages.yml` deploys
them to GitHub Pages:
- on a push to `main` or `world-assets` that touches `site/`;
- or by hand, from *Actions → Pages → Run workflow*.

| Page | URL once live | Used by |
|---|---|---|
| `site/privacy.html` | `https://defzeke.github.io/Studymon/privacy.html` | `PRIVACY_URL` in `scripts/ui/settings.gd`, Play Console → App content → Privacy policy |
| `site/terms.html` | `https://defzeke.github.io/Studymon/terms.html` | `TERMS_URL` |
| `site/support.html` | `https://defzeke.github.io/Studymon/support.html` | `SUPPORT_URL`, the store listing's website |
| `site/index.html` | `https://defzeke.github.io/Studymon/` | the store listing's website |

**One-time setup** (needs admin rights on the repo):
- GitHub → Settings → Pages → Source: **GitHub Actions**.
- The `github-pages` environment only deploys from allowed branches. If a run from `world-assets` is
  refused, add that branch under Settings → Environments → `github-pages`, or merge `site/` to `main`
  first.

**Contact:** the pages send people to the developer email shown on the Play listing. Google requires
that email anyway, so no address is written in the repo.

**What the privacy policy claims, and where the code proves it:**

| Claim | Code |
|---|---|
| The save lives on the phone, with Export / Import | `SaveManager` ([`data-model.md`](data-model.md)) |
| A copy goes to Play Games Saved Games only when signed in, on Android | `CloudSave` ([`data-model.md`](data-model.md) §8) |
| Nothing is sent before consent; withdrawing it stops all AI calls | `GameState.ai_consent`, [`api-backend.md`](api-backend.md) §6 |
| What is sent: reviewer text or file and the world name; for "More questions" the saved text and existing questions; essays and Identification near-misses with the answer key | `api.gd` `upload_reviewer()`, `grade_battle_question()`; `backend/main.py` request models |
| HTTPS only | `api.gd` refuses a non-`https://` `RELEASE_URL` in release builds |
| The server stores nothing it is sent | `backend/main.py`: no database, no file writes |
| Reports are logged with their text | `main.py` `report()` → `log.warning` |
| Per-address counts for the day, in memory | `main.py` `over_limit()` |
| Logs deleted after about 7 days | Render's Hobby (free) workspace retention ([Render logging](https://render.com/docs/logging)) |
| Cloudflare does not train on Workers AI content | [Cloudflare Workers AI privacy](https://developers.cloudflare.com/workers-ai/platform/privacy/) |
| No ads, analytics or accounts | no SDK besides the Play Games plugin; the only network calls are in `api.gd` |

---

## 2. Data safety form

| Question | Answer |
|---|---|
| Does the app collect or share any required user data types? | **Yes** |
| Is all user data encrypted in transit? | **Yes** (HTTPS) |
| Can users ask for their data to be deleted? | **Yes**: Settings → Delete my data erases the phone's save and the Play Games copy. The server keeps nothing, apart from logs that expire |
| Data shared with third parties? | **No**. Cloudflare and Render are service providers acting for us, which the form does not count as sharing |

Data types (all **collected, not shared, optional**, purpose **App functionality**):

| Data type | Ephemeral? | What it is |
|---|---|---|
| Photos and videos → **Photos** | Yes | a photo of a reviewer, read once to write questions |
| Files and docs | Yes | a reviewer PDF, Word or PowerPoint file, read once |
| App activity → **Other user-generated content** | No, because reports are logged | pasted reviewer text, typed battle answers, the text of reported questions and feedback |

Not collected: location, personal info (name, email, IDs), financial info, contacts, messages,
health, audio, web history, device IDs, crash logs and diagnostics.

**Re-check when filling in the form:**
- IP addresses are in the host's logs and in the day's in-memory limits. They are not used for
  location. Read the form's current guidance on IP addresses before answering.
- The Play Games copy is stored by Google in the player's own Drive. Our server never receives it.
  Confirm how the form treats data handled by Google Play services itself.

---

## 3. App content declarations

| Item | Answer |
|---|---|
| Ads | **No ads** |
| App access | All functionality is available without special access. Note that the AI needs the player's consent, which the reviewer gives in the app (§5) |
| Target audience | **13–15, 16–17, 18+**. Not under 13 |
| Appeals to children? | No. A study tool for teens and adults, but the cartoon companion may be questioned; the answer rests on the 13+ study audience |
| News, government, financial, health | No |
| Generative AI | Yes: questions and grades. In-app **Report** on generated questions (World Builder) and on feedback (battle → Review answers), as Google's AI-generated content policy requires |

### Content rating (IARC questionnaire)

| Topic | Answer |
|---|---|
| Category | Game (trivia / educational) |
| Violence | **Yes, fantasy only**: quiz battles between robot companions shown as hits and shakes; no blood, no humans hurt |
| Sexuality, profanity, drugs, alcohol, tobacco, gambling, horror | No |
| Users interact or share content with each other | **No**: nothing a player makes reaches another player |
| Shares the user's location | No |
| Digital purchases | No (crystals are earned only) |
| Unrestricted internet access | No (only the study server) |

---

## 4. Listing text

**App name** (≤ 30): `Studymon`

**Short description** (≤ 80):
> Raise Kuiz and turn your own notes into quiz battles. Free, no ads.

**Full description** (≤ 4000):
> Studymon turns studying into an adventure with a companion that grows with you.
>
> RAISE KUIZ
> Look after Kuiz, your little study robot: charge it, feed it, play with it, dress it up and watch
> it level up across four cosy rooms.
>
> STUDY FROM YOUR OWN MATERIAL
> Paste your notes or pick a PDF, Word or PowerPoint file, or a photo of your reviewer. Studymon's AI
> turns it into Multiple Choice, Identification and Essay questions in the reviewer's own language,
> and you can edit or add questions yourself.
>
> EXPLORE AND BATTLE
> Every reviewer becomes an island world. Walk it with your explorer, take on Challenge Houses and
> Gyms, and face the Champion. Answer well to land strong hits; finish a run with a full review of
> your answers.
>
> KEEP IT UP
> Flashcards, a focus timer, a daily goal and a streak keep you studying a little every day.
>
> FREE AND PRIVATE
> No ads and no accounts. Your progress stays on your phone, with an optional copy in your Google
> Play Games account so it follows you to a new phone. The AI only reads what you choose to upload,
> after you agree, and nothing you upload is kept.
>
> For students and learners aged 13 and up.

**Category:** Educational (as a Game, so Play Games Services work). **Tags:** trivia, education.
**Contact email:** the developer's. **Website:** the `site/` index.

---

## 5. Review notes

For *App access* and the closed or production review:

> Studymon needs no login. To see the AI features:
> 1. Finish the short intro (type any name).
> 2. In the Study Room, tap **Study**, then **+ New World**.
> 3. Give the world a name, paste the text below, tap **Extract questions with AI**, and tap
>    **I agree** on the AI notice.
> 4. The questions appear within about a minute; the server sleeps when idle. Tap
>    **Confirm & Play** to walk the world and battle its trainers.
>
> Each question in the World Builder has a **Report** button, and each answer in a battle's
> **Review answers** has a report flag (⚑).

Sample reviewer to paste (original, about 150 words):

> Photosynthesis is the process plants, algae and some bacteria use to turn light energy into
> chemical energy. It takes place in the chloroplasts, mainly in the leaves. Chlorophyll, the green
> pigment in the chloroplasts, absorbs red and blue light and reflects green light. The process has
> two stages. The light-dependent reactions happen in the thylakoid membranes: water is split,
> oxygen is released as a by-product, and the energy is stored in ATP and NADPH. The Calvin cycle
> happens in the stroma: it uses ATP, NADPH and carbon dioxide from the air to build glucose. The
> enzyme RuBisCO fixes carbon dioxide in the first step of the Calvin cycle. The overall equation is
> 6CO2 + 6H2O + light → C6H12O6 + 6O2. Light intensity, carbon dioxide level and temperature all
> limit the rate of photosynthesis.

---

## 6. Graphics

| Asset | Size | Status |
|---|---|---|
| App icon | 512 × 512 PNG, 32-bit | **missing**: Godot's default `icon.svg` today ([`tasks.md`](tasks.md) F2) |
| Adaptive icon (in the export) | foreground and background, 432 × 432 | missing |
| Feature graphic | 1024 × 500 PNG or JPG | missing |
| Phone screenshots | 2–8, portrait 9:16 (for example 1080 × 1920) | to take on a phone in F3: home with Kuiz, the World Builder with questions, the island map, a battle hit, the Review answers list, flashcards, Settings → Privacy & data |
