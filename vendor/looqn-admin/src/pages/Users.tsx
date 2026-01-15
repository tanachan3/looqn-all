import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  where,
  writeBatch,
  type DocumentData,
  type DocumentSnapshot,
  type QueryDocumentSnapshot,
} from 'firebase/firestore'
import { type FormEvent, useEffect, useState } from 'react'
import { db } from '../firebase'
import type { UserRecord } from '../types'
import { formatTimestamp } from '../utils/format'

const mapUser = (
  docSnap: QueryDocumentSnapshot<DocumentData> | DocumentSnapshot<DocumentData>,
): UserRecord => {
  const data = docSnap.data()
  if (!data) {
    return { id: docSnap.id }
  }
  return {
    id: docSnap.id,
    displayName: typeof data.displayName === 'string' ? data.displayName : null,
    createdAt: data.createdAt,
    isNotificationEnabled:
      typeof data.isNotificationEnabled === 'boolean' ? data.isNotificationEnabled : null,
    location: data.location ?? null,
  }
}

const formatLocation = (user: UserRecord) => {
  if (user.location) {
    return `${user.location.latitude.toFixed(5)}, ${user.location.longitude.toFixed(5)}`
  }
  return '-'
}

export function UsersPage() {
  const [userIdQuery, setUserIdQuery] = useState('')
  const [displayNameQuery, setDisplayNameQuery] = useState('')
  const [limitCount, setLimitCount] = useState(50)
  const [users, setUsers] = useState<UserRecord[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [deletingId, setDeletingId] = useState<string | null>(null)

  const loadUsers = async () => {
    setLoading(true)
    setError(null)
    setNotice(null)
    try {
      const trimmedId = userIdQuery.trim()
      if (trimmedId) {
        const userSnap = await getDoc(doc(db, 'users', trimmedId))
        if (!userSnap.exists()) {
          setUsers([])
          setNotice('該当するユーザーが見つかりませんでした。')
          return
        }
        const mapped = mapUser(userSnap)
        const filtered = displayNameQuery.trim()
          ? mapped.displayName?.includes(displayNameQuery.trim()) ?? false
          : true
        setUsers(filtered ? [mapped] : [])
        if (!filtered) {
          setNotice('条件に一致するユーザーがありません。')
        }
        return
      }

      const usersQuery = query(
        collection(db, 'users'),
        orderBy('createdAt', 'desc'),
        limit(limitCount),
      )
      const snapshot = await getDocs(usersQuery)
      const list = snapshot.docs.map((docSnap) => mapUser(docSnap))
      const trimmedName = displayNameQuery.trim().toLowerCase()
      const filtered = trimmedName
        ? list.filter((user) => (user.displayName ?? '').toLowerCase().includes(trimmedName))
        : list
      setUsers(filtered)
      if (filtered.length === 0) {
        setNotice('条件に一致するユーザーがありません。')
      }
    } catch (err) {
      console.error(err)
      setError('ユーザー情報の取得に失敗しました。')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadUsers()
  }, [])

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    loadUsers()
  }

  const handleDelete = async (user: UserRecord) => {
    const confirmMessage =
      'ユーザーを削除して users_withdraw に移動します。関連する user_login も削除し user_login_deleted にコピーします。よろしいですか？'
    if (!window.confirm(confirmMessage)) return
    try {
      setError(null)
      setNotice(null)
      setDeletingId(user.id)
      const userRef = doc(db, 'users', user.id)
      const userSnap = await getDoc(userRef)
      if (!userSnap.exists()) {
        setError('ユーザーが見つからないため削除できませんでした。')
        return
      }

      const loginQuery = query(collection(db, 'user_login'), where('user_id', '==', user.id))
      const loginSnapshot = await getDocs(loginQuery)

      const batch = writeBatch(db)
      batch.set(doc(db, 'users_withdraw', user.id), userSnap.data())
      batch.delete(userRef)

      loginSnapshot.docs.forEach((loginDoc) => {
        batch.set(doc(db, 'user_login_deleted', loginDoc.id), loginDoc.data())
        batch.delete(loginDoc.ref)
      })

      await batch.commit()
      setUsers((prev) => prev.filter((item) => item.id !== user.id))
      setNotice('ユーザーを削除し、users_withdraw と user_login_deleted に移動しました。')
    } catch (err) {
      console.error(err)
      setError('ユーザーの削除に失敗しました。')
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <section>
      <h2>ユーザー検索</h2>
      <p className="muted">ユーザーIDと表示名で検索できます。</p>
      {error && <p className="alert">{error}</p>}
      <div className="panel">
        <h3>検索条件</h3>
        <form className="form" onSubmit={handleSubmit}>
          <label>
            ユーザーID
            <input
              value={userIdQuery}
              onChange={(event) => setUserIdQuery(event.target.value)}
              placeholder="完全一致で検索"
            />
          </label>
          <label>
            表示名
            <input
              value={displayNameQuery}
              onChange={(event) => setDisplayNameQuery(event.target.value)}
              placeholder="部分一致で検索"
            />
          </label>
          <label>
            表示上限
            <select
              value={limitCount}
              onChange={(event) => setLimitCount(Number(event.target.value))}
            >
              <option value={20}>20件</option>
              <option value={50}>50件</option>
              <option value={100}>100件</option>
            </select>
          </label>
          <div className="actions">
            <button className="button" type="submit" disabled={loading}>
              検索
            </button>
          </div>
        </form>
      </div>

      <div className="panel">
        <h3>検索結果</h3>
        <p className="muted">表示件数: {users.length}</p>
        {loading ? (
          <p>読み込み中...</p>
        ) : (
          <div className="table">
            <div className="table-row users header with-actions">
              <span>ユーザーID</span>
              <span>表示名</span>
              <span>通知設定</span>
              <span>位置情報</span>
              <span>作成日時</span>
              <span>操作</span>
            </div>
            {users.map((user) => (
              <div key={user.id} className="table-row users with-actions">
                <span>{user.id}</span>
                <span>{user.displayName ?? '-'}</span>
                <span>
                  {typeof user.isNotificationEnabled === 'boolean'
                    ? user.isNotificationEnabled
                      ? '有効'
                      : '無効'
                    : '-'}
                </span>
                <span>{formatLocation(user)}</span>
                <span>{formatTimestamp(user.createdAt)}</span>
                <span>
                  <button
                    type="button"
                    className="button danger"
                    disabled={deletingId === user.id}
                    onClick={() => handleDelete(user)}
                  >
                    削除
                  </button>
                </span>
              </div>
            ))}
            {notice && <p className="muted">{notice}</p>}
          </div>
        )}
      </div>
    </section>
  )
}
