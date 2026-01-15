import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  type DocumentData,
  type DocumentSnapshot,
  type QueryDocumentSnapshot,
} from 'firebase/firestore'
import { type FormEvent, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { db } from '../firebase'
import type { PostRecord } from '../types'
import { decryptText, decryptUserId } from '../utils/crypto'
import { formatTimestamp } from '../utils/format'

const mapPost = async (
  docSnap: QueryDocumentSnapshot<DocumentData> | DocumentSnapshot<DocumentData>,
): Promise<PostRecord> => {
  const data = docSnap.data()
  if (!data) {
    return { id: docSnap.id }
  }

  const rawUserId =
    typeof data.user_id === 'string'
      ? data.user_id
      : typeof data.posterId === 'string'
        ? data.posterId
        : typeof data.poster_id === 'string'
          ? data.poster_id
          : null
  const userId =
    rawUserId && rawUserId.length > 0 ? await decryptUserId(rawUserId) : null
  const text = typeof data.text === 'string' ? await decryptText(data.text) : null

  return {
    id: docSnap.id,
    text,
    posterName: typeof data.posterName === 'string' ? data.posterName : null,
    userId,
    createdAt: data.createdAt,
    parent: typeof data.parent === 'string' ? data.parent : null,
    address: typeof data.address === 'string' ? data.address : null,
    geohash: typeof data.geohash === 'string' ? data.geohash : null,
    position: data.position ?? null,
  }
}

const formatLocation = (post: PostRecord) => {
  if (post.position) {
    return `${post.position.latitude.toFixed(5)}, ${post.position.longitude.toFixed(5)}`
  }
  return '-'
}

export function PostsSearchPage() {
  const [postId, setPostId] = useState('')
  const [userIdQuery, setUserIdQuery] = useState('')
  const [keyword, setKeyword] = useState('')
  const [limitCount, setLimitCount] = useState(50)
  const [collectionName, setCollectionName] = useState<'posts' | 'posts_purged'>('posts')
  const [posts, setPosts] = useState<PostRecord[]>([])
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [sortKey, setSortKey] = useState<
    'id' | 'poster' | 'text' | 'location' | 'createdAt' | 'parent'
  >('createdAt')
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc')

  const handleSort = (
    key: 'id' | 'poster' | 'text' | 'location' | 'createdAt' | 'parent',
  ) => {
    if (sortKey === key) {
      setSortDirection((prev) => (prev === 'asc' ? 'desc' : 'asc'))
      return
    }
    setSortKey(key)
    setSortDirection('asc')
  }

  const applySort = (list: PostRecord[]) => {
    const direction = sortDirection === 'asc' ? 1 : -1
    return [...list].sort((a, b) => {
      const textValue = (value?: string | null) => (value ?? '').toLowerCase()
      const compareText = (valueA?: string | null, valueB?: string | null) =>
        textValue(valueA).localeCompare(textValue(valueB))

      const compareNumber = (valueA?: number | null, valueB?: number | null) => {
        const safeA = valueA ?? -Infinity
        const safeB = valueB ?? -Infinity
        if (safeA === safeB) return 0
        return safeA > safeB ? 1 : -1
      }

      const compareCreatedAt = () => {
        const timeA = a.createdAt?.toMillis() ?? 0
        const timeB = b.createdAt?.toMillis() ?? 0
        return compareNumber(timeA, timeB)
      }

      const compareLocation = () => {
        const addressCompare = compareText(a.address, b.address)
        if (addressCompare !== 0) return addressCompare
        const latCompare = compareNumber(a.position?.latitude ?? null, b.position?.latitude ?? null)
        if (latCompare !== 0) return latCompare
        return compareNumber(a.position?.longitude ?? null, b.position?.longitude ?? null)
      }

      let base = 0
      switch (sortKey) {
        case 'id':
          base = compareText(a.id, b.id)
          break
        case 'poster':
          base = compareText(a.posterName ?? a.userId ?? '', b.posterName ?? b.userId ?? '')
          if (base === 0) {
            base = compareText(a.userId, b.userId)
          }
          break
        case 'text':
          base = compareText(a.text, b.text)
          break
        case 'location':
          base = compareLocation()
          break
        case 'createdAt':
          base = compareCreatedAt()
          break
        case 'parent':
          base = compareText(a.parent, b.parent)
          break
        default:
          base = 0
      }
      return base * direction
    })
  }

  const loadPosts = async () => {
    setLoading(true)
    setError(null)
    setNotice(null)
    try {
      const trimmedId = postId.trim()
      if (trimmedId) {
        const postSnap = await getDoc(doc(db, collectionName, trimmedId))
        if (!postSnap.exists()) {
          setPosts([])
          setNotice('該当する投稿が見つかりませんでした。')
          return
        }
        setPosts([await mapPost(postSnap)])
        return
      }

      const postsQuery = query(
        collection(db, collectionName),
        orderBy('createdAt', 'desc'),
        limit(limitCount),
      )
      const snapshot = await getDocs(postsQuery)
      const list = await Promise.all(snapshot.docs.map((docSnap) => mapPost(docSnap)))
      const trimmedKeyword = keyword.trim().toLowerCase()
      const trimmedUserId = userIdQuery.trim().toLowerCase()
      const filtered = list.filter((post) => {
        if (trimmedUserId) {
          const candidate = post.userId?.toLowerCase() ?? ''
          if (!candidate.includes(trimmedUserId)) {
            return false
          }
        }
        if (!trimmedKeyword) {
          return true
        }
        const candidates = [
          post.id,
          post.userId,
          post.posterName,
          post.text,
          post.address,
          post.parent,
          post.geohash,
        ]
        return candidates.some(
          (candidate) => typeof candidate === 'string' && candidate.toLowerCase().includes(trimmedKeyword),
        )
      })
      const sorted = applySort(filtered)
      setPosts(sorted)
      if (sorted.length === 0) {
        setNotice('条件に一致する投稿がありません。')
      }
    } catch (err) {
      console.error(err)
      setError('投稿情報の取得に失敗しました。')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadPosts()
  }, [])

  useEffect(() => {
    setPosts((prev) => applySort(prev))
  }, [sortKey, sortDirection])

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    loadPosts()
  }

  return (
    <section>
      <h2>投稿検索</h2>
      <p className="muted">投稿IDの直接参照やキーワード検索ができます。</p>
      {error && <p className="alert">{error}</p>}
      <div className="panel">
        <h3>検索条件</h3>
        <form className="form" onSubmit={handleSubmit}>
          <label>
            投稿ID
            <input
              value={postId}
              onChange={(event) => setPostId(event.target.value)}
              placeholder="完全一致で検索"
            />
          </label>
          <label>
            投稿者ID
            <input
              value={userIdQuery}
              onChange={(event) => setUserIdQuery(event.target.value)}
              placeholder="user_id で検索"
            />
          </label>
          <label>
            キーワード
            <input
              value={keyword}
              onChange={(event) => setKeyword(event.target.value)}
              placeholder="本文・投稿者・住所など"
            />
          </label>
          <label>
            対象コレクション
            <select
              value={collectionName}
              onChange={(event) =>
                setCollectionName(event.target.value as 'posts' | 'posts_purged')
              }
            >
              <option value="posts">posts</option>
              <option value="posts_purged">posts_purged</option>
            </select>
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
        <p className="muted">表示件数: {posts.length}</p>
        {loading ? (
          <p>読み込み中...</p>
        ) : (
          <div className="table">
            <div className="table-row posts header">
              <button
                type="button"
                className="sort-button"
                onClick={() => handleSort('id')}
              >
                投稿ID
                <span className="sort-indicator">
                  {sortKey === 'id' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                </span>
              </button>
              <button
                type="button"
                className="sort-button"
                onClick={() => handleSort('poster')}
              >
                投稿者
                <span className="sort-indicator">
                  {sortKey === 'poster' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                </span>
              </button>
              <button
                type="button"
                className="sort-button"
                onClick={() => handleSort('text')}
              >
                本文
                <span className="sort-indicator">
                  {sortKey === 'text' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                </span>
              </button>
              <button
                type="button"
                className="sort-button"
                onClick={() => handleSort('location')}
              >
                住所/位置
                <span className="sort-indicator">
                  {sortKey === 'location' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                </span>
              </button>
              <button
                type="button"
                className="sort-button"
                onClick={() => handleSort('createdAt')}
              >
                作成日時
                <span className="sort-indicator">
                  {sortKey === 'createdAt' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                </span>
              </button>
              <button
                type="button"
                className="sort-button"
                onClick={() => handleSort('parent')}
              >
                親投稿
                <span className="sort-indicator">
                  {sortKey === 'parent' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                </span>
              </button>
            </div>
            {posts.map((post) => (
              <div key={post.id} className="table-row posts">
                <span>
                  <Link
                    to={
                      collectionName === 'posts'
                        ? `/posts/${post.id}`
                        : `/posts/${post.id}?collection=posts_purged`
                    }
                  >
                    {post.id}
                  </Link>
                </span>
                <span>
                  <div>{post.posterName ?? '-'}</div>
                  <div className="post-meta">{post.userId ?? '-'}</div>
                </span>
                <span className="post-text">{post.text ?? '-'}</span>
                <span>
                  <div>{post.address ?? '-'}</div>
                  <div className="post-meta">{formatLocation(post)}</div>
                </span>
                <span>{formatTimestamp(post.createdAt)}</span>
                <span>{post.parent ?? '-'}</span>
              </div>
            ))}
            {notice && <p className="muted">{notice}</p>}
          </div>
        )}
      </div>
    </section>
  )
}
