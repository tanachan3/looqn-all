import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Firebase Admin SDKの初期化
admin.initializeApp();

// 新しい投稿を処理する関数
export const postMsg = functions.https.onCall(async (data, context) => {
  try {
    const { text, userId, userName, userImageUrl, position } = data;

    // パラメータのバリデーション
    if (!text || !userId || !userName || !userImageUrl || !position) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The function must be called with all required parameters.",
      );
    }

    // Firestoreに新しいドキュメントを作成
    const newPostRef = admin.firestore().collection("posts").doc();
    await newPostRef.set({
      text: text,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      posterName: userName,
      posterImageUrl: userImageUrl,
      posterId: userId,
      position: new admin.firestore.GeoPoint(
        position.latitude,
        position.longitude,
      ),
      latitude: position.latitude,
      longitude: position.longitude,
    });

    return { success: true };
  } catch (error) {
    console.error("Error posting message:", error);
    throw new functions.https.HttpsError(
      "unknown",
      "An error occurred while posting the message.",
    );
  }
});

// 古い投稿を定期的にパージし、purgedコレクションに移動する関数
export const purgeOldPosts = functions.pubsub
  .schedule("5 * * * *")
  .onRun(async (context) => {
    const firestore = admin.firestore();
    const postsRef = firestore.collection("posts");
    const purgedPostsRef = firestore.collection("posts_purged");
    const now = admin.firestore.Timestamp.now();

    // 10日前のタイムスタンプを取得
    const cutoff = now.toMillis() - 24 * 60 * 60 * 1000;
    const oldPostsQuery = postsRef.where(
      "createdAt",
      "<",
      admin.firestore.Timestamp.fromMillis(cutoff),
    );

    const oldPostsSnapshot = await oldPostsQuery.get();
    const batch = firestore.batch();

    for (const doc of oldPostsSnapshot.docs) {
      const postData = doc.data();
      const postId = doc.id;

      // purgedコレクションにドキュメントを追加
      const purgedPostRef = purgedPostsRef.doc(postId);
      batch.set(purgedPostRef, {
        ...postData,
        purgedAt: admin.firestore.Timestamp.now(),
      });

      // サブコレクション 'readStatus' を取得
      const readStatusRef = postsRef.doc(postId).collection("readStatus");
      const readStatusSnapshot = await readStatusRef.get();

      // サブコレクション 'readStatus' を purged コレクションにコピー
      for (const statusDoc of readStatusSnapshot.docs) {
        const statusData = statusDoc.data();
        batch.set(
          purgedPostRef.collection("readStatus").doc(statusDoc.id),
          statusData,
        );
      }

      // オリジナルのドキュメントとサブコレクションを削除
      batch.delete(doc.ref);
      for (const statusDoc of readStatusSnapshot.docs) {
        batch.delete(statusDoc.ref);
      }
    }

    return batch.commit();
  });

// 新しいメッセージが投稿されたときにすべてのユーザーにプッシュ通知を送信する関数
export const sendPushNotificationOnNewPost = functions.firestore
  .document("posts/{postId}")
  .onCreate(async (snap, context) => {
    const newPost = snap.data();
    const firestore = admin.firestore();
    const usersRef = firestore.collection("users");
    const userSnapshots = await usersRef.get();
    const messages: admin.messaging.Message[] = [];

    // すべてのユーザーに対してプッシュ通知を作成
    userSnapshots.forEach((userDoc) => {
      const userData = userDoc.data();
      const userToken = userData.fcmToken;

      if (userToken) {
        messages.push({
          token: userToken,
          notification: {
            title: "新しい投稿",
            body: newPost.text,
          },
        });
      }
    });

    // プッシュ通知の送信
    if (messages.length > 0) {
      await admin.messaging().sendAll(messages);
      console.log(`Sent ${messages.length} notifications`);
    } else {
      console.log("No users found with FCM tokens");
    }
  });


// OpenAIを利用してAIメッセージを取得する関数

export const fetchAiMessages = functions.https.onCall(async (data) => {
  // 1) 件数ガード（1〜5）
  const rawCount = Number(data?.count);
  const safeCount = Math.max(1, Math.min(5, Number.isFinite(rawCount) ? Math.floor(rawCount) : 1));
  functions.logger.info("fetchAiMessages v=2025-09-12-2", { data });
  const pos = coercePosition(data?.position);
  // functions.logger.info("coercedPosition", { pos });
  functions.logger.info(`coercedPosition ${JSON.stringify(pos)}`);

  // ← 必須にするなら、coerce後に判定
  if (!pos) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "position.latitude / position.longitude are required numbers."
    );
  }
  // 2) 位置 & 言語 & 半径
  // const position = data?.position as { latitude?: number; longitude?: number } | undefined;
  const position = pos;
  if (!position || typeof position.latitude !== "number" || typeof position.longitude !== "number") {
    throw new functions.https.HttpsError("invalid-argument", "position.latitude / position.longitude are required numbers.");
  }
  const language =
    typeof data?.language === "string" && data.language.trim() !== "" ? data.language.trim() : "日本語";

  const radiusMeters =
    Number.isFinite(Number(data?.radiusMeters)) && Number(data?.radiusMeters) > 0
      ? Math.min(1500, Math.max(100, Math.floor(Number(data.radiusMeters))))
      : 500;

  const placeHint =
    typeof data?.placeHint === "string" && data.placeHint.trim() !== "" ? data.placeHint.trim() : "";

  const debugEnabled = Boolean(data?.debug);

  // 3) OpenAI
  const apiKey = process.env.OPENAI_API_KEY || (functions.config().openai?.key as string | undefined);
  if (!apiKey) throw new functions.https.HttpsError("failed-precondition", "OpenAI APIキーが設定されていません。");
  const OpenAI = (await import("openai")).default;
  const client = new OpenAI({ apiKey });

  // 4) utils
  const clampUtf8 = (s: string, maxBytes = 300) => {
    let bytes = 0, out = "";
    for (const ch of s) {
      const len = Buffer.byteLength(ch, "utf8");
      if (bytes + len > maxBytes) break;
      out += ch; bytes += len;
    }
    return out;
  };
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const distanceMeters = (lat1: number, lon1: number, lat2: number, lon2: number) => {
    const R = 6371000, dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  };
  const pickNameForLanguage = (tags: Record<string, string> | undefined, lang: string): string | null => {
    if (!tags) return null;
    const isJa = /^(ja|日本語)/i.test(lang);
    const c = [isJa ? tags["name:ja"] : "", !isJa ? tags["name:en"] : "", tags["name"], tags["official_name"]]
      .filter(Boolean) as string[];
    return c[0] || null;
  };

  // 5) OSM: 半径r以内の公共系固有名詞（駅/公園/博物館/大学/図書館/神社寺/幹線道路/広場/河川）
  async function fetchProperNounsFromOSM(lat: number, lon: number, r: number, lang: string): Promise<string[]> {
    const q = `
[out:json][timeout:25];
(
  node(around:${r},${lat},${lon})["railway"="station"];
  way(around:${r},${lat},${lon})["railway"="station"];
  relation(around:${r},${lat},${lon})["railway"="station"];

  node(around:${r},${lat},${lon})["public_transport"="station"];
  way(around:${r},${lat},${lon})["public_transport"="station"];
  relation(around:${r},${lat},${lon})["public_transport"="station"];

  node(around:${r},${lat},${lon})["leisure"="park"];
  way(around:${r},${lat},${lon})["leisure"="park"];
  relation(around:${r},${lat},${lon})["leisure"="park"];

  node(around:${r},${lat},${lon})["tourism"="museum"];
  way(around:${r},${lat},${lon})["tourism"="museum"];
  relation(around:${r},${lat},${lon})["tourism"="museum"];

  node(around:${r},${lat},${lon})["amenity"="university"];
  way(around:${r},${lat},${lon})["amenity"="university"];
  relation(around:${r},${lat},${lon})["amenity"="university"];

  node(around:${r},${lat},${lon})["amenity"="library"];
  way(around:${r},${lat},${lon})["amenity"="library"];
  relation(around:${r},${lat},${lon})["amenity"="library"];

  node(around:${r},${lat},${lon})["historic"~"^(shrine|temple)$"];
  way(around:${r},${lat},${lon})["historic"~"^(shrine|temple)$"];
  relation(around:${r},${lat},${lon})["historic"~"^(shrine|temple)$"];

  way(around:${r},${lat},${lon})["highway"~"^(primary|trunk)$"]["name"];
  relation(around:${r},${lat},${lon})["highway"~"^(primary|trunk)$"]["name"];

  node(around:${r},${lat},${lon})["place"="square"];
  way(around:${r},${lat},${lon})["place"="square"];
  relation(around:${r},${lat},${lon})["place"="square"];

  way(around:${r},${lat},${lon})["waterway"="river"]["name"];
  relation(around:${r},${lat},${lon})["waterway"="river"]["name"];
);
out center tags;`.trim();

    try {
      const overpassUrl = "https://overpass-api.de/api/interpreter";
      const res = await fetch(overpassUrl, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
        body: `data=${encodeURIComponent(q)}`
      });
      if (!res.ok) throw new Error(`Overpass HTTP ${res.status}`);
      const json = await res.json();

      type Elem = { lat?: number; lon?: number; center?: { lat: number; lon: number }; tags?: Record<string, string> };
      const centerOf = (e: Elem) => (e.lat != null && e.lon != null ? { lat: e.lat, lon: e.lon } : e.center || null);

      const seen = new Set<string>();
      const items: { name: string; dist: number }[] = [];
      for (const e of (json.elements || []) as Elem[]) {
        const name = pickNameForLanguage(e.tags, lang);
        if (!name) continue;
        const c = centerOf(e); if (!c) continue;
        const d = distanceMeters(lat, lon, c.lat, c.lon);
        if (d > r + 5) continue;
        const key = name.trim(); if (seen.has(key)) continue;
        seen.add(key); items.push({ name: key, dist: d });
      }
      items.sort((a, b) => a.dist - b.dist);
      return items.slice(0, 10).map(i => i.name);
    } catch (err) {
      functions.logger.warn("Overpass fetch failed", { err: String(err) });
      return [];
    }
  }

  // 6) 固有名詞: クライアント優先→OSM
  const properNounsClient: string[] = Array.isArray(data?.properNouns)
    ? data.properNouns.map((x: unknown) => String(x).trim()).filter(Boolean)
    : [];
  let properNouns = [...new Set(properNounsClient)].slice(0, 10);
  if (properNouns.length === 0) {
    properNouns = await fetchProperNounsFromOSM(position.latitude!, position.longitude!, radiusMeters, language);
  }

  // 7) 固有名詞を出力言語にローカライズ
  async function localizeProperNouns(nouns: string[], lang: string): Promise<{ orig: string; display: string }[]> {
    if (!nouns.length) return [];
    const sys = `
You are a toponym localizer.
Translate or transliterate each public place name into exactly "${lang}".
Rules:
- Return JSON only: {"terms":[{"orig":"...","display":"..."}, ...]}
- Use exonyms in ${lang} if well-known; otherwise natural transliteration (e.g., katakana for Japanese).
- Keep the place type if part of the proper name; otherwise omit.
- Keep pairs aligned and do not add/drop items.
`.trim();

    const usr = JSON.stringify({ nouns });
    const resp = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [{ role: "system", content: sys }, { role: "user", content: usr }],
      response_format: { type: "json_object" },
      temperature: 0,
      max_tokens: 300
    });

    try {
      const content = resp?.choices?.[0]?.message?.content ?? `{"terms":[]}`;
      const parsed = JSON.parse(content);
      const arr = Array.isArray(parsed?.terms) ? parsed.terms : [];
      const pairs = arr
        .map((t: any) => ({ orig: String(t?.orig || "").trim(), display: String(t?.display || "").trim() }))
        .filter(t => t.orig && t.display);
      const seen = new Set<string>(), out: { orig: string; display: string }[] = [];
      for (const p of pairs) { if (seen.has(p.display)) continue; seen.add(p.display); out.push(p); }
      return out.slice(0, 10);
    } catch {
      return [];
    }
  }
  const localizedPairs = await localizeProperNouns(properNouns, language);
  const displayNouns = localizedPairs.map(p => p.display);

  // 8) ペルソナ詳細（年齢・性別・教育レベル）を提案 or 受取
  type Education = "secondary" | "vocational" | "undergraduate" | "graduate" | "self-taught" | "unspecified";
  type PersonaDetail = {
    label: string;
    age: "teen" | "20s" | "30s-40s" | "50+";
    gender: "male" | "female" | "nonbinary" | "unspecified";
    education: Education;
  };

  async function proposePersonasDetailed(opts: {
    latitude: number; longitude: number; language: string; count: number; placeHint?: string; nearby?: string[];
  }): Promise<PersonaDetail[]> {
    const { latitude, longitude, language, count, placeHint, nearby } = opts;
    const utcNow = new Date().toISOString();
    const hemisphere = latitude >= 0 ? "north" : "south";

    const system = `
You are a localization strategist for a hyperlocal social app.
From coordinates + current UTC (and optional nearby public places), infer suitable public-space roles.
Return exactly N *diverse* personas with age, gender, and education metadata.

Output rules:
- JSON only: {"personas":[{"label":"...","age":"teen|20s|30s-40s|50+","gender":"male|female|nonbinary|unspecified","education":"secondary|vocational|undergraduate|graduate|self-taught"}]}
- Labels: concise English (3–8 words), internal use only.
- Aim for diversity across age/gender/education (when N ≥ 3, include ≥ 3 distinct education buckets if plausible).
- Public-space roles only (commuter, office worker, runner, photo walker, campus student, market-goer, neighbor, etc.).
- Avoid stereotypes & sensitive content; respectful & neutral. No private businesses.
`.trim();

    const user = `
Latitude: ${latitude}
Longitude: ${longitude}
Hemisphere: ${hemisphere}
Current UTC: ${utcNow}
Target message language (context only): ${language}
Nearby public places (may be ignored): ${nearby && nearby.length ? nearby.join(", ") : "none"}
Optional hint: ${placeHint || "none"}
N: ${count}

Return only the JSON object described above.
`.trim();

    const resp = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
      response_format: { type: "json_object" },
      temperature: 0.35,
      presence_penalty: 0.2,
      max_tokens: 360
    });

    try {
      const content = resp?.choices?.[0]?.message?.content ?? `{"personas":[]}`;
      const parsed = JSON.parse(content);
      const arr = Array.isArray(parsed?.personas) ? parsed.personas : [];

      const normEdu = (s: string): Education => {
        const t = String(s || "").toLowerCase().replace(/\s+/g, "");
        if (/^(secondary|highschool|hs)$/.test(t)) return "secondary";
        if (/^(vocational|technical|tech|trade)$/.test(t)) return "vocational";
        if (/^(undergrad(uate)?|college|bachelor)$/.test(t)) return "undergraduate";
        if (/^(graduate|postgrad(uate)?|master|phd|doctor)$/.test(t)) return "graduate";
        if (/^(selftaught|self\-taught|autodidact)$/.test(t)) return "self-taught";
        return "unspecified";
      };

      const cleaned = arr.map((x: any) => {
        const label = String(x?.label || "").trim();
        const ageRaw = String(x?.age || "").trim().toLowerCase();
        const genderRaw = String(x?.gender || "").trim().toLowerCase();
        const eduRaw = String(x?.education || "").trim().toLowerCase();
        if (!label) return null;

        const age = (["teen", "20s", "30s-40s", "50+"].includes(ageRaw) ? ageRaw : "20s") as PersonaDetail["age"];
        const gender = (["male", "female", "nonbinary", "unspecified"].includes(genderRaw) ? genderRaw : "unspecified") as PersonaDetail["gender"];
        const education = normEdu(eduRaw);

        return { label, age, gender, education } as PersonaDetail;
      }).filter(Boolean) as PersonaDetail[];

      const seen = new Set<string>(), out: PersonaDetail[] = [];
      for (const p of cleaned) { if (seen.has(p.label)) continue; seen.add(p.label); out.push(p); }
      return out.slice(0, count);
    } catch {
      return [];
    }
  }

  // 8-2) personas: リクエスト優先（文字列 or 詳細）→ 不足分は自動提案 → フォールバック
  const reqPersonasRaw: any[] = Array.isArray(data?.personas) ? data.personas : [];
  const reqPersonasDetail: PersonaDetail[] = reqPersonasRaw
    .map((p) => {
      if (p && typeof p === "object" && p.label) {
        const age = (["teen", "20s", "30s-40s", "50+"].includes(p.age) ? p.age : "20s") as PersonaDetail["age"];
        const gender = (["male", "female", "nonbinary", "unspecified"].includes(p.gender) ? p.gender : "unspecified") as PersonaDetail["gender"];
        const education = (["secondary", "vocational", "undergraduate", "graduate", "self-taught", "unspecified"].includes(p.education)
          ? p.education
          : "unspecified") as Education;
        return { label: String(p.label), age, gender, education };
      } else if (typeof p === "string") {
        return { label: p, age: "20s", gender: "unspecified", education: "unspecified" } as PersonaDetail;
      }
      return null;
    })
    .filter(Boolean) as PersonaDetail[];

  let personasDetail: PersonaDetail[] = reqPersonasDetail.slice(0, safeCount);
  if (personasDetail.length < safeCount) {
    const autos = await proposePersonasDetailed({
      latitude: position.latitude!,
      longitude: position.longitude!,
      language,
      count: safeCount,
      placeHint,
      nearby: displayNouns
    });
    for (let i = personasDetail.length; i < safeCount; i++) personasDetail.push(autos[i] || null as any);
  }

  // フォールバック（分散）
  const fb: PersonaDetail[] = [
    { label: "commuter (polite)", age: "30s-40s", gender: "unspecified", education: "undergraduate" },
    { label: "student (casual)", age: "20s", gender: "unspecified", education: "undergraduate" },
    { label: "neighbor (friendly)", age: "50+", gender: "unspecified", education: "secondary" },
    { label: "runner (brisk)", age: "30s-40s", gender: "unspecified", education: "vocational" },
    { label: "photo walker", age: "20s", gender: "unspecified", education: "self-taught" },
  ];
  for (let i = 0; i < safeCount; i++) if (!personasDetail[i]) personasDetail[i] = fb[i % fb.length];

  // 9) スタイルプラン（口調ばらけ）
  const isJa = /^(ja|日本語)/i.test(language);
  const stylePlan = (() => {
    const palette = ["polite", "casual", "playful", "reflective", "brisk"];
    return Array.from({ length: safeCount }, (_, i) => palette[i % palette.length]);
  })();

  if (debugEnabled) {
    console.log("[fetchAiMessages][DEBUG] personasDetail =", JSON.stringify(personasDetail, null, 2));
    console.log("[fetchAiMessages][DEBUG] stylePlan      =", JSON.stringify(stylePlan));
    console.log("[fetchAiMessages][DEBUG] displayNouns   =", JSON.stringify(displayNouns));
  }

  // 10) system/user プロンプト
  const utcNow = new Date().toISOString();
  const hemisphere = position.latitude! >= 0 ? "north" : "south";
  const minProperUse = displayNouns.length > 0 ? Math.min(2, safeCount) : 0;

  const styleDefinitions = isJa
    ? `
- polite: 丁寧体中心（〜ます／〜ませんか／〜でしょう）。絵文字なし。
- casual: ため口・素直な感想（〜だ／〜する／〜かな？／〜かも）。
- playful: 軽い驚きや短い感嘆。絵文字はこのスタイルのみ可（セット全体で最大1個）。
- reflective: 観察→内省。比喩は少量。
- brisk: テンポ速め。短文・体言止め・呼びかけ。
`.trim()
    : `
- polite: courteous, indirect, no emoji.
- casual: friendly and direct, light contractions.
- playful: short exclamations/interjections; allow at most one emoji in the whole set.
- reflective: observation → mild introspection; a bit of metaphor is OK.
- brisk: snappy rhythm; short clauses and suggestions.
`.trim();

  const variationRules = isJa
    ? `
- セット全体で文末を少なくとも3種類（「〜ですね／〜だ／〜かな？／〜よ／〜かも」など）に分散。
- 同一語尾の完全一致を繰り返さない。
- 句読点（。！？や?）と一人称（私／僕／一人称なし）を分散。
- 絵文字は 'playful' のメッセージでのみ最大1個。
`.trim()
    : `
- Use at least three different endings across the set (".", "!", "?", tag questions like "right?", "isn't it?").
- Don't repeat an identical sentence ending across messages.
- Vary punctuation and first-person usage (I / no pronoun) across messages.
- Emoji only in the 'playful' style (max 1 total).
`.trim();

  const firstPersonRules = isJa
    ? `- 一人称（任意・性別を明示しない）：male→「僕」も可、female→「私」、nonbinary/unspecified→「私」または一人称なし。使いすぎない。`
    : `- First-person pronoun "I" is allowed when natural. Do not mention gender explicitly.`;

  const personaListForPrompt = personasDetail
    .map((p, i) => `${i + 1}. ${p.label} | age=${p.age} | gender=${p.gender} | edu=${p.education}`)
    .join("\n");

  const systemPrompt = `
You are a copywriter for a hyperlocal social app. Write brief, grounded lines that feel like someone standing there.

Output:
- JSON only: {"messages":[...]} — no extra text or code fences.
- Language: exactly "${language}" (no mixing, no translation notes).

Content constraints:
- Anonymous: no PII, no exact addresses, no private/small business names.
- Prefer public/generic terms when needed (station area, park entrance, riverbank).
- Include a light location/sensory cue (breeze, shade, traffic noise, footsteps, evening light).
- Infer local **time of day** and **season** from coordinates+UTC; don't mention time zone or UTC. Numeric HH:mm not required. Mention both once per message.
- Proper nouns: if a whitelist is provided, use **at most one** per message, **only** from the whitelist; include a noun in at least ${minProperUse} messages. All places must be within ${radiusMeters}m.
- Length: about **two sentences per message**, total length **≤ 300 bytes (UTF-8)**.
- No self-reference and no hashtags.

Persona & style (MANDATORY):
- Style each message by its index persona (do NOT print persona name/age/gender/education).
- Use the **style plan** for sentence endings, interjections, emoji usage, and rhythm.
- ${firstPersonRules}
- Education influences vocabulary & cadence (subtle; no explicit mention):
  • secondary → everyday words, short sentences, energetic or direct.
  • vocational → practical verbs, action-oriented suggestions, concrete phrasing.
  • undergraduate → casual & curious; light connectors ok.
  • graduate → slightly formal, precise wording, mild hedging (e.g., “perhaps / かも”).
  • self-taught → exploratory tone, “learning/trying” vibe without stating it.
- Avoid stereotypes; be respectful and neutral.

Style definitions (for ${language}):
${styleDefinitions}

Variation requirements:
${variationRules}

Personas by message index (1..N) — internal guide only:
${personaListForPrompt}

Style plan by message index (1..N):
${stylePlan.map((s, i) => `${i + 1}. ${s}`).join("\n")}
`.trim();

  const userPrompt = `
Analyze this place using only coordinates and current UTC.
Latitude: ${position.latitude}
Longitude: ${position.longitude}
Hemisphere: ${hemisphere}
Current UTC time: ${utcNow}
Language: ${language}
Optional place hint (may be ignored): ${placeHint || "none"}

Display whitelist of allowed public proper nouns (0 or 1 per message; within ${radiusMeters}m):
${displayNouns.length ? displayNouns.map(n => `- ${n}`).join("\n") : "- (none)"}

Task: Produce exactly ${safeCount} messages styled by the persona of each index, tied to that area as observations or gentle questions.
Return only: {"messages":["...", "..."]}.
`.trim();

  const completion = await client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }],
    response_format: { type: "json_object" },
    temperature: 0.5,        // 口調差を強める
    presence_penalty: 0.9,   // 語彙/語尾の重複を強く抑制
    frequency_penalty: 0.2,
    top_p: 0.9,
    max_tokens: 520
  });

  // 11) パース & 300バイトclamp
  const content = completion.choices?.[0]?.message?.content ?? `{"messages":[]}`;
  let messages: string[] = [];
  try {
    const parsed = JSON.parse(content);
    if (Array.isArray(parsed?.messages)) {
      messages = parsed.messages
        .map((x: unknown) => String(x).trim())
        .filter(Boolean)
        .map(s => clampUtf8(s, 300));
    }
  } catch (e) {
    messages = [];
    functions.logger.error("JSON parse failed", e as Error, { content });
  }

  if (debugEnabled) {
    const mapped = messages.map((msg, i) => ({
      index: i + 1,
      persona: personasDetail[i],              // { label, age, gender, education }
      style: stylePlan[i],                     // "polite" | "casual" | ...
      usedProperNoun: displayNouns.find(n => msg.includes(n)) || null,
      lengthBytes: Buffer.byteLength(msg, "utf8"),
      preview: msg.slice(0, 80)
    }));
    console.log("[fetchAiMessages][DEBUG] messageMapping =", JSON.stringify(mapped, null, 2));
  }

  // 12) ログ
  functions.logger.info("fetchAiMessages", {
    requested: rawCount,
    normalizedCount: safeCount,
    messagesCount: messages.length,
    language,
    position: { lat: position.latitude, lng: position.longitude },
    radiusMeters,
    placeHint,
    properNounsDisplay: displayNouns,
    personasDetail
  });

  return { messages };
});
function coercePosition(input: any): { latitude: number; longitude: number } | undefined {
  if (!input || typeof input !== "object") return undefined;

  // キー名のゆらぎを吸収
  let lat: any =
    input.latitude ?? input.lat ?? input.Lat ?? input.LAT;
  let lng: any =
    input.longitude ?? input.lng ?? input.lon ?? input.long ?? input.Longitude ?? input.LONGITUDE;

  // 文字列なら数値化
  if (typeof lat === "string") lat = Number(lat);
  if (typeof lng === "string") lng = Number(lng);

  // 数値チェック
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return undefined;

  return { latitude: Number(lat), longitude: Number(lng) };
}