import { Timestamp, collection, doc, getDoc, getDocs, limit, query, where } from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { useLocation, useParams } from 'react-router-dom'
import { moderatePost } from '../api/functions'
import { db } from '../firebase'
import type { ModerationAction, Post, Report } from '../types'
import { decryptText, decryptUserId } from '../utils/crypto'
import { formatTimestamp } from '../utils/format'

export function PostDetailPage() {
  const { postId } = useParams()
  const location = useLocation()
  const collectionParam = new URLSearchParams(location.search).get('collection')
  const collectionName = collectionParam === 'posts_purged' ? 'posts_purged' : 'posts'
  const [post, setPost] = useState<Post | null>(null)
  const [reports, setReports] = useState<Report[]>([])
  const [actions, setActions] = useState<ModerationAction[]>([])
  const [reasonCode, setReasonCode] = useState('')
  const [note, setNote] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const fetchPost = async () => {
    if (!postId) return
    const postSnap = await getDoc(doc(db, collectionName, postId))
    if (postSnap.exists()) {
      const data = postSnap.data() as Record<string, unknown>
      const rawUserId =
        typeof data.user_id === 'string'
          ? data.user_id
          : typeof data.posterId === 'string'
            ? data.posterId
            : null
      const userId =
        rawUserId && rawUserId.length > 0 ? await decryptUserId(rawUserId) : null
      const text = typeof data.text === 'string' ? await decryptText(data.text) : null
      const rawParent =
        typeof data.parent === 'string'
          ? data.parent
          : typeof data.parentId === 'string'
            ? data.parentId
            : typeof data.parent_id === 'string'
              ? data.parent_id
              : null
      setPost({
        id: postSnap.id,
        ...(data as Omit<Post, 'id'>),
        text,
        posterName: typeof data.posterName === 'string' ? data.posterName : null,
        userId,
        parent: rawParent,
        address: typeof data.address === 'string' ? data.address : null,
        geohash: typeof data.geohash === 'string' ? data.geohash : null,
        position: data.position ?? null,
      })
    } else {
      setPost(null)
    }
  }

  const fetchReports = async () => {
    if (!postId) return
    const reportQuery = query(collection(db, 'reports'), where('postId', '==', postId), limit(50))
    const legacyReportQuery = query(
      collection(db, 'reports'),
      where('reportedPostId', '==', postId),
      limit(50),
    )
    const [reportSnap, legacyReportSnap] = await Promise.all([
      getDocs(reportQuery),
      getDocs(legacyReportQuery),
    ])
    const normalizeReport = (docId: string, data: Record<string, unknown>): Report => {
      const postIdValue =
        typeof data.postId === 'string'
          ? data.postId
          : typeof data.reportedPostId === 'string'
            ? data.reportedPostId
            : ''
      const reasonCode =
        typeof data.reasonCode === 'string'
          ? data.reasonCode
          : typeof data.reason === 'string'
            ? data.reason
            : undefined
      const createdAt =
        data.createdAt instanceof Timestamp
          ? data.createdAt
          : data.timestamp instanceof Timestamp
            ? data.timestamp
            : undefined
      const reporterUid =
        typeof data.reporterUid === 'string'
          ? data.reporterUid
          : typeof data.reportedBy === 'string'
            ? data.reportedBy
            : null
      const state = typeof data.state === 'string' ? data.state : 'open'
      const processed = typeof data.processed === 'boolean' ? data.processed : null

      return {
        id: docId,
        postId: postIdValue,
        reasonCode,
        reporterUid,
        createdAt,
        state,
        processed,
      }
    }
    const list = [
      ...reportSnap.docs.map((docSnap) => normalizeReport(docSnap.id, docSnap.data())),
      ...legacyReportSnap.docs.map((docSnap) => normalizeReport(docSnap.id, docSnap.data())),
    ]
    const uniqueById = new Map(list.map((report) => [report.id, report]))
    const sorted = Array.from(uniqueById.values()).sort((a, b) => {
      const aTime = a.createdAt ? a.createdAt.toMillis() : 0
      const bTime = b.createdAt ? b.createdAt.toMillis() : 0
      return bTime - aTime
    })
    setReports(sorted)
  }

  const fetchActions = async () => {
    if (!postId) return
    const actionQuery = query(
      collection(db, 'moderation_actions'),
      where('targetType', '==', 'post'),
      where('targetId', '==', postId),
      orderBy('createdAt', 'desc'),
      limit(10),
    )
    const actionSnap = await getDocs(actionQuery)
    const list = actionSnap.docs.map((docSnap) => ({
      id: docSnap.id,
      ...(docSnap.data() as Omit<ModerationAction, 'id'>),
    }))
    setActions(list)
  }

  useEffect(() => {
    const load = async () => {
      try {
        await Promise.all([fetchPost(), fetchReports(), fetchActions()])
      } catch (err) {
        console.error(err)
        setError('投稿情報の取得に失敗しました。')
      }
    }

    load()
  }, [postId, collectionName])

  const handleModerate = async (action: 'hide' | 'restore' | 'delete') => {
    if (!postId) return
    try {
      setError(null)
      setMessage(null)
      await moderatePost({
        postId,
        action,
        reasonCode: reasonCode || undefined,
        note: note || undefined,
      })
      setMessage(`${action} を実行しました。`)
      await Promise.all([fetchPost(), fetchActions()])
    } catch (err) {
      console.error(err)
      setError('操作に失敗しました。')
    }
  }

  if (!postId) {
    return <p className="alert">投稿IDが見つかりません。</p>
  }

  return (
    <section>
      <h2>投稿詳細</h2>
      <p className="muted">
        投稿の状態と通報履歴を確認します。対象コレクション: {collectionName}
      </p>
      {error && <p className="alert">{error}</p>}
      {message && <p className="success">{message}</p>}
      <div className="panel">
        <h3>投稿情報</h3>
        {post ? (
          <dl className="detail">
            <div>
              <dt>ID</dt>
              <dd>{post.id}</dd>
            </div>
            <div>
              <dt>ステータス</dt>
              <dd>{post.status ?? 'unknown'}</dd>
            </div>
            <div>
              <dt>作成日時</dt>
              <dd>{formatTimestamp(post.createdAt)}</dd>
            </div>
            <div>
              <dt>投稿者</dt>
              <dd>{post.posterName ?? '-'}</dd>
            </div>
            <div>
              <dt>投稿者ID</dt>
              <dd>{post.userId ?? '-'}</dd>
            </div>
            <div>
              <dt>本文</dt>
              <dd className="detail-text">{post.text ?? '-'}</dd>
            </div>
            <div>
              <dt>親投稿ID</dt>
              <dd>{post.parent ?? '-'}</dd>
            </div>
            <div>
              <dt>住所</dt>
              <dd>{post.address ?? '-'}</dd>
            </div>
            <div>
              <dt>ジオハッシュ</dt>
              <dd>{post.geohash ?? '-'}</dd>
            </div>
            <div>
              <dt>最終通報</dt>
              <dd>{formatTimestamp(post.lastReportedAt)}</dd>
            </div>
          </dl>
        ) : (
          <p>投稿情報が見つかりません。</p>
        )}
      </div>

      <div className="panel">
        <h3>操作</h3>
        <div className="form">
          <label>
            reasonCode
            <input value={reasonCode} onChange={(event) => setReasonCode(event.target.value)} />
          </label>
          <label>
            note
            <input value={note} onChange={(event) => setNote(event.target.value)} />
          </label>
        </div>
        <div className="actions">
          <button className="button" onClick={() => handleModerate('hide')}>
            非表示
          </button>
          <button className="button" onClick={() => handleModerate('restore')}>
            復帰
          </button>
          <button className="button danger" onClick={() => handleModerate('delete')}>
            削除
          </button>
        </div>
      </div>

      <div className="panel">
        <h3>通報一覧</h3>
        <div className="table">
          <div className="table-row header">
            <span>ID</span>
            <span>理由</span>
            <span>日時</span>
            <span>状態</span>
          </div>
          {reports.map((report) => (
            <div key={report.id} className="table-row">
              <span>{report.id}</span>
              <span>{report.reasonCode ?? '-'}</span>
              <span>{formatTimestamp(report.createdAt)}</span>
              <span>{report.state ?? '-'}</span>
            </div>
          ))}
        </div>
        {reports.length === 0 && <p className="muted">通報はありません。</p>}
      </div>

      <div className="panel">
        <h3>監査ログ（最新10件）</h3>
        <div className="table">
          <div className="table-row header">
            <span>日時</span>
            <span>操作</span>
            <span>担当者</span>
            <span>メモ</span>
          </div>
          {actions.map((action) => (
            <div key={action.id} className="table-row">
              <span>{formatTimestamp(action.createdAt)}</span>
              <span>{action.action}</span>
              <span>{action.operatorEmail ?? action.operatorUid}</span>
              <span>{action.note ?? '-'}</span>
            </div>
          ))}
        </div>
        {actions.length === 0 && <p className="muted">ログはありません。</p>}
      </div>
    </section>
  )
}
