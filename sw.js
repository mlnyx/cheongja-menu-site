// 청자다방 Service Worker — Web Push 알림 수신용
// GitHub Pages basePath 안에서 동작 (예: /cheongja-menu-site/sw.js)

self.addEventListener('install', (e) => {
  self.skipWaiting()
})

self.addEventListener('activate', (e) => {
  e.waitUntil(self.clients.claim())
})

// Push 메시지 수신
self.addEventListener('push', (event) => {
  let payload = { title: '청자다방', body: '알림이 도착했어요', url: '/' }
  try {
    if (event.data) payload = { ...payload, ...event.data.json() }
  } catch {}

  const options = {
    body: payload.body,
    icon: payload.icon || './icon-192.png',
    badge: payload.badge || './icon-192.png',
    data: { url: payload.url },
    vibrate: [200, 100, 200],
    tag: payload.tag || 'cheongja-default',
    renotify: true,
    requireInteraction: true,
  }

  event.waitUntil(self.registration.showNotification(payload.title, options))
})

// 알림 클릭 → 해당 URL 로 이동 (이미 열린 탭이 있으면 focus)
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const target = event.notification.data?.url || '/'
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.includes(target) && 'focus' in c) return c.focus()
      }
      if (self.clients.openWindow) return self.clients.openWindow(target)
    }),
  )
})
