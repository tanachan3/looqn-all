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
import { formatTimestamp } from '../utils/format'

const mapPost = (
  docSnap: QueryDocumentSnapshot<DocumentData> | DocumentSnapshot<DocumentData>,
): PostRecord => {
  const data = docSnap.data()
  if (!data) {
    return { id: docSnap.id }
  }
  const userId =
    typeof data.user_id === 'string'
      ? data.user_id
      : typeof data.posterId === 'string'
        ? data.posterId
        : typeof data.poster_id === 'string'
          ? data.poster_id
          : null

  return {
    id: docSnap.id,
    text: typeof data.text === 'string' ? data.text : null,
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
  const [keyword, setKeyword] = useState('')
  const [limitCount, setLimitCount] = useState(50)
  const [posts, setPosts] = useState<PostRecord[]>([])
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const loadPosts = async () => {
    setLoading(true)
    setError(null)
    setNotice(null)
    try {
      const trimmedId = postId.trim()
      if (trimmedId) {
        const postSnap = await getDoc(doc(db, 'posts', trimmedId))
        if (!postSnap.exists()) {
          setPosts([])
          setNotice('該当する投稿が見つかりませんでした。')
          return
        }
        setPosts([mapPost(postSnap)])
        return
      }

      const postsQuery = query(
        collection(db, 'posts'),
        orderBy('createdAt', 'desc'),
        limit(limitCount),
      )
      const snapshot = await getDocs(postsQuery)
      const list = snapshot.docs.map((docSnap) => mapPost(docSnap))
      const trimmedKeyword = keyword.trim().toLowerCase()
      const filtered = trimmedKeyword
        ? list.filter((post) => {
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
              (candidate) =>
                typeof candidate === 'string' && candidate.toLowerCase().includes(trimmedKeyword),
            )
          })
        : list
      setPosts(filtered)
      if (filtered.length === 0) {
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
            キーワード
            <input
              value={keyword}
              onChange={(event) => setKeyword(event.target.value)}
              placeholder="本文・投稿者・住所など"
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
        <p className="muted">表示件数: {posts.length}</p>
        {loading ? (
          <p>読み込み中...</p>
        ) : (
          <div className="table">
            <div className="table-row posts header">
              <span>投稿ID</span>
              <span>投稿者</span>
              <span>本文</span>
              <span>住所/位置</span>
              <span>作成日時</span>
              <span>親投稿</span>
            </div>
            {posts.map((post) => (
              <div key={post.id} className="table-row posts">
                <span>
                  <Link to={`/posts/${post.id}`}>{post.id}</Link>
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
