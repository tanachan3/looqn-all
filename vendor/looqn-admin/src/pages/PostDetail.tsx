import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  where,
} from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { moderatePost } from '../api/functions'
import { db } from '../firebase'
import type { ModerationAction, Post, Report } from '../types'
import { formatTimestamp } from '../utils/format'

export function PostDetailPage() {
  const { postId } = useParams()
  const [post, setPost] = useState<Post | null>(null)
  const [reports, setReports] = useState<Report[]>([])
  const [actions, setActions] = useState<ModerationAction[]>([])
  const [reasonCode, setReasonCode] = useState('')
  const [note, setNote] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const fetchPost = async () => {
    if (!postId) return
    const postSnap = await getDoc(doc(db, 'posts', postId))
    if (postSnap.exists()) {
      setPost({ id: postSnap.id, ...(postSnap.data() as Omit<Post, 'id'>) })
    } else {
      setPost(null)
    }
  }

  const fetchReports = async () => {
    if (!postId) return
    const reportQuery = query(
      collection(db, 'reports'),
      where('postId', '==', postId),
      orderBy('createdAt', 'desc'),
      limit(50),
    )
    const reportSnap = await getDocs(reportQuery)
    const list = reportSnap.docs.map((docSnap) => ({
      id: docSnap.id,
      ...(docSnap.data() as Omit<Report, 'id'>),
    }))
    setReports(list)
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
  }, [postId])

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
      <p className="muted">投稿の状態と通報履歴を確認します。</p>
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
