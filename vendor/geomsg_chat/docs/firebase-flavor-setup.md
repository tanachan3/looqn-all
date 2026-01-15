# geomsg_chat

Flutter製位置情報共有アプリの開発環境/本番環境をFirebaseプロジェクト単位で切り替えるための手順メモです。

## 初期設定フロー
プロジェクトをクローンした直後や、初めてFirebaseプロジェクトの切り替え対応を行う際は次の手順で環境を整えます。

1. **FlutterFire CLI の準備**
   まだ導入していない場合は以下でインストールします。
   ```bash
   dart pub global activate flutterfire_cli
   ```

2. **本番用 `firebase_options` の生成**
   既存ファイルを上書きしても問題ありません。
   ```bash
   flutterfire configure \
     --project=geomsg-4d728 \
     --out=lib/firebase_options_prod.dart
   ```

3. **開発用 `firebase_options` の生成**
   ```bash
   flutterfire configure \
     --project=LooQN-dev \
     --out=lib/firebase_options_dev.dart
   ```

4. **iOS/macOS 向け設定ファイルの配置**
   上記2つのコマンドを実行すると `GoogleService-Info.plist` が生成されるため、次の場所にコピーします。
   - 本番: `ios/Runner/Configs/Prod/GoogleService-Info.plist`
   - 開発: `ios/Runner/Configs/Dev/GoogleService-Info.plist`

5. **Android 向け設定ファイルの配置**
   `google-services.json` を以下に配置します。
   - 本番: `android/app/src/prod/google-services.json`
   - 開発: `android/app/src/dev/google-services.json`

6. **依存関係の取得**
   Flutter依存関係を一括取得します。
   ```bash
   flutter pub get
   ```

> **メモ:** リポジトリに含まれる `android/app/src/dev/google-services.json` や `ios/Runner/Configs/*/GoogleService-Info.plist` はダミー値が含まれているため、必ずFlutterFire CLIで再生成してください。

### Google サインイン用 OAuth クライアントの確認

Google ログインを利用する場合は、Firebase コンソールの **[Authentication] → [Sign-in method] → [Google]** で `Web client` と `Android client` の OAuth クライアントが発行されていることを確認してください。特に開発用プロジェクト (`LooQN-dev`) では以下の手順を忘れずに行います。

1. **SHA-1 / SHA-256 フィンガープリントの登録**
   - Android Studio もしくは `./gradlew signingReport` で `debug`/`release` キーストアのフィンガープリントを取得し、Firebase コンソールの `アプリを編集` 画面に追加します。
   - 新しいフィンガープリントを保存すると、自動的に Google 用 OAuth クライアント ID が再生成され、`google-services.json` の `oauth_client` セクションに反映されます。
2. **最新の設定ファイルを再ダウンロード**
   - 変更を反映するため、`google-services.json` と `GoogleService-Info.plist` を再ダウンロードし、`android/app/src/<flavor>/` と `ios/Runner/Configs/<Flavor>/` に置き換えます。
   - `google-services.json` に `"default_web_client_id"` が含まれない状態だと ID トークンが取得できず、`PlatformException(sign_in_failed, statusCode=DEVELOPER_ERROR(10))` などのエラーが発生します。
3. **Flutter 実行時のキャッシュをクリア**
   - Android Studio を再起動するか、`flutter clean` → `flutter pub get` を実行して古い Google Play Services キャッシュが残らないようにします。

> Google の OAuth クライアントが揃っていれば、今回の修正で実装したフォールバック処理（`GoogleAuthProvider` 経由）でもサインインできます。いずれにしても設定ファイルは Firebase 側の最新状態と揃えておくことを推奨します。

## 開発/本番の切り替え方法
実行時に `--flavor` と `--dart-define=FLAVOR=` を揃えて指定すると、`lib/main_<flavor>.dart` が正しいFirebaseプロジェクトを読み込みます。

### ローカル実行・ビルド例
| 対象 | コマンド例 |
| --- | --- |
| 開発ビルド (Android) | `flutter run --flavor dev -t lib/main_dev.dart --dart-define=FLAVOR=dev` |
| 本番ビルド (Android APK) | `flutter build apk --flavor prod -t lib/main_prod.dart --dart-define=FLAVOR=prod` |
| 本番ビルド (Android aab) | `flutter build appbundle --flavor prod -t lib/main_prod.dart --dart-define=FLAVOR=prod` |
| 開発ビルド (iOS) | `flutter run --flavor dev -t lib/main_dev.dart --dart-define=FLAVOR=dev` |
| 本番ビルド (iOS) | `flutter build ios --flavor prod -t lib/main_prod.dart --dart-define=FLAVOR=prod` |
| Web (開発) | `flutter run -d chrome --dart-define=FLAVOR=dev -t lib/main_dev.dart` |
| Web (本番) | `flutter build web --dart-define=FLAVOR=prod -t lib/main_prod.dart` |

## Android の設定ポイント
- `android/app/build.gradle` に `dev` / `prod` フレーバーを追加し、`applicationIdSuffix` や `resValue` でアプリ名を分離しています。
- 各フレーバー専用の `google-services.json` を `src/<flavor>/` 配下に配置してください。

## iOS / macOS の設定ポイント
- `ios/Runner/Configs/Dev` および `ios/Runner/Configs/Prod` に Firebase 設定ファイルを配置しています。
- Xcode では `Runner` スキームを複製し、`Runner-dev` (Debug/Release/Profiling) などフレーバー別のビルド設定を作成した上で、`Copy Bundle Resources` に該当フレーバーの `GoogleService-Info.plist` を登録してください。
- `BUNDLE_ID` も `net.looqn.app.dev` のように開発用へ変更することをおすすめします。

## Firebase CLI
プロジェクトルートに `.firebaserc` を作成し、以下のようにエイリアスを登録しておくと便利です。
```json
{
  "projects": {
    "default": "geomsg-4d728",
    "prod": "geomsg-4d728",
    "dev": "LooQN-dev"
  }
}
```
CLIで利用する際は `firebase deploy --project prod` のように明示的に指定してください。CI/CDでは `--project` を必ず指定することで切り替え漏れを防げます。

## 補足
- 背景タスクやWorkManagerはフレーバーに関係なく動作します。
- Flavorsは `--dart-define=FLAVOR=<dev|prod>` と連動しているため、CI/CDでも同じ値を指定してください。

## Git Tips
- `git add --renormalize .` を実行すると、`.gitattributes` の変更を既存ファイルに反映できます。
