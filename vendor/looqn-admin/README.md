# LooQN 管理画面 (Admin Console)

運用オペレーター向けの管理画面です。Firebase Authentication (Google) と Firestore を利用し、読み取りはフロント、重要操作は Cloud Functions 経由で実行します。

## 主要機能

- Google ログイン (Firebase Auth)
- custom claims による role 制御 (`operator` / `admin`)
- 通報キュー、投稿詳細、問い合わせ管理
- 重要操作は Cloud Functions を呼び出し、`moderation_actions` に監査ログを残す

## 環境変数

`.env.example` をコピーして `.env` を作成してください。

```bash
cp .env.example .env
```

```env
VITE_FIREBASE_API_KEY=your-api-key
VITE_FIREBASE_AUTH_DOMAIN=your-auth-domain
VITE_FIREBASE_PROJECT_ID=your-project-id
VITE_FIREBASE_STORAGE_BUCKET=your-storage-bucket
VITE_FIREBASE_MESSAGING_SENDER_ID=your-messaging-sender-id
VITE_FIREBASE_APP_ID=your-app-id
```

## ローカル起動

```bash
npm install
npm run dev
```

## Firebase 設定

### Google Provider の有効化

Firebase Console → Authentication → Sign-in method → Google を有効化してください。

### custom claims の付与 (例)

Admin SDK を利用して `role` を付与します。

```ts
import { getAuth } from 'firebase-admin/auth'

await getAuth().setCustomUserClaims(uid, { role: 'operator' })
```

付与後はクライアント側で `getIdTokenResult(true)` を呼び出して反映します。

## Cloud Functions (API) 想定

- `moderatePost` : `{ postId, action, reasonCode?, note? }`
- `replyInquiry` : `{ inquiryId, text }`
- `updateInquiry` : `{ inquiryId, state?, assigneeUid? }`

全ての操作は `moderation_actions` に記録してください。

## Firestore Security Rules 方針

- 管理画面ユーザーは `posts`, `reports`, `inquiries`, `inquiry_messages`, `moderation_actions` を **read-only**
- 書き込みは Cloud Functions から行う

## 画面構成

- `/login` : ログイン
- `/` : ダッシュボード
- `/reports` : 通報キュー
- `/posts/:postId` : 投稿詳細
- `/inquiries` : 問い合わせ一覧
- `/inquiries/:id` : 問い合わせ詳細
- `/settings` : ログイン情報 / role
