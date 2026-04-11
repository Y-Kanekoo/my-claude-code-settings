---
name: kb-frontend
description: フロントエンドのナレッジベース。React/Vue/Tailwind等のパターンを蓄積
user-invocable: true
entry_count: 10
last_updated: 2026-02-27
---

# フロントエンド ナレッジベース

React/Vue/Tailwind等のフロントエンド技術で学んだパターンを記録する。

## React パターン

### React Hooksの呼び出し順序ルール

**状況**: `useCallback`を早期リターン（`if (isLoading) return ...`）の後に配置してしまい、Hooksルール違反になった
**解決策**: 全てのHooks（useState, useCallback, useMemo等）は早期リターンの前、コンポーネントのトップレベルに配置する

```tsx
// NG: 早期リターンの後にuseCallback
function Component() {
  const { data, isLoading } = useQuery(...);
  if (isLoading) return <Loading />;  // 早期リターン
  const renderItem = useCallback(...);  // Hooksルール違反！
}

// OK: 全Hooksを早期リターンの前に配置
function Component() {
  const { data, isLoading } = useQuery(...);
  const renderItem = useCallback(({ item }) => (
    <ItemCard item={item} />
  ), []);
  if (isLoading) return <Loading />;  // 早期リターンはHooksの後
}
```

### React Query楽観的更新パターン

**状況**: PATCH操作でサーバー応答を待たずにUIを即座に更新したい
**解決策**: `onMutate`でキャッシュバックアップ→即座更新、`onError`でロールバック、`onSettled`で再取得

```tsx
const updateMutation = useMutation({
  mutationFn: (data) => apiFetch(`/items/${data.id}`, { method: "PATCH", body: data }),
  onMutate: async (updated) => {
    await queryClient.cancelQueries({ queryKey: ["items"] });
    const previous = queryClient.getQueryData<Item[]>(["items"]);
    queryClient.setQueryData<Item[]>(["items"], (old) =>
      old?.map((item) => item.id === updated.id ? { ...item, ...updated } : item) ?? []
    );
    return { previous };
  },
  onError: (_err, _vars, context) => {
    if (context?.previous) queryClient.setQueryData(["items"], context.previous);
  },
  onSettled: () => queryClient.invalidateQueries({ queryKey: ["items"] }),
});
```

## 状態管理

### React Queryキャッシュ無効化の連鎖

**状況**: フィードバック送信後に履歴一覧と該当セッション詳細の両方を最新化したい
**解決策**: `onSuccess`で複数のqueryKeyを`invalidateQueries`する

```tsx
const feedbackMutation = useMutation({
  mutationFn: (data) => apiFetch(`/diagnoses/${data.sessionId}/feedback`, { method: "POST", body: data }),
  onSuccess: (_data, variables) => {
    queryClient.invalidateQueries({ queryKey: ["diagnoses", "history"] });
    queryClient.invalidateQueries({ queryKey: ["diagnoses", variables.sessionId] });
  },
});
```

## CSS/Tailwind

（スタイリングのパターンをここに追記）

## トラブルシューティング

### npm installでpeer dependency競合

**状況**: react-domのpeer dependencyでインストールが失敗
**解決策**: `npm install --legacy-peer-deps` を使用

### NetInfoモックが動かない

**状況**: `@react-native-community/netinfo`のモックでdefaultエクスポートが認識されない
**解決策**: `__esModule: true` と `default` エクスポートを両方指定する

```js
jest.mock("@react-native-community/netinfo", () => ({
  __esModule: true,
  default: { addEventListener: jest.fn(), fetch: jest.fn() },
}));
```

## Tips

### FlatListのrenderItemメモ化

`useCallback`でrenderItemをメモ化し、コンポーネント自体も`React.memo`で囲むと再レンダリングが40-60%削減される

## React Native テスト

### React Navigation モックパターン
<!-- added: 2026-02-27 -->

**状況**: テストで `createNativeStackNavigator` を使った画面コンポーネントをレンダリングしたい
**解決策**: `<>{children}</>` + `MockStackScreen` でモック。全Screenが同時レンダリングされる制約がある

```tsx
jest.mock("@react-navigation/native-stack", () => ({
  createNativeStackNavigator: () => ({
    Navigator: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    Screen: ({ component: Component, ...props }: { component: React.ComponentType; name: string }) => (
      <Component {...props} />
    ),
  }),
}));
```

**注意**: 実際のナビゲーションスタックと異なり、全Screenが一度にレンダリングされる。個別画面のテストには向くが、遷移テストには不向き。

### setTimeout クリーンアップパターン
<!-- added: 2026-02-27 -->

**状況**: コンポーネント内で `setTimeout` を使うとアンマウント後にメモリリークや状態更新エラーが発生する
**解決策**: `useRef` でタイマーIDを保持し、`useEffect` のクリーンアップで確実にクリアする

```tsx
const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

useEffect(() => {
  return () => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
    }
  };
}, []);

// タイマー設定時
timerRef.current = setTimeout(() => {
  // 処理
}, 3000);
```

**ポイント**: `ReturnType<typeof setTimeout>` でNode.jsとブラウザ環境の型差異を吸収。`NodeJS.Timeout` は環境依存。

### React Query テスト: デフォルトオプションとqueryKeys
<!-- added: 2026-02-27 -->

**状況**: React Queryの設定値やqueryKey生成関数をテストしたい
**解決策**: `queryClient.getDefaultOptions()` で設定値を検証。queryKeys関数は毎回新しい配列を返すため参照比較は `.not.toBe()` を使う

```tsx
// デフォルトオプションの検証
const defaults = queryClient.getDefaultOptions();
expect(defaults.queries?.staleTime).toBe(5 * 60 * 1000);

// queryKeys関数の参照非同一性を検証
const key1 = queryKeys.products.list();
const key2 = queryKeys.products.list();
expect(key1).toEqual(key2);     // 値は同一
expect(key1).not.toBe(key2);    // 参照は異なる（毎回新しい配列）
```
