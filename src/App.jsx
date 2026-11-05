import { useEffect, useMemo, useState } from 'react'
import { onAuthStateChanged, signInWithEmailAndPassword, signOut } from 'firebase/auth'
import {
  onValue,
  push,
  ref,
  remove,
  serverTimestamp,
  set,
  update,
} from 'firebase/database'
import { auth, database } from './firebase'
import './App.css'

const blankProduct = {
  name: '',
  category: '',
  price: '',
  stock: '',
  image: '',
}

const CATEGORY_OPTIONS = ['Laptop', 'GPU', 'CPU', 'Storage', 'Accessories', 'Other']
const MAX_IMAGE_FILE_SIZE = 5 * 1024 * 1024
const MAX_COMPRESSED_IMAGE_SIZE = 280 * 1024

function isImageSource(value) {
  return /^(https?:\/\/|data:image\/)/i.test(String(value ?? ''))
}

async function compressImageForDatabase(file) {
  const bitmap = await createImageBitmap(file)
  const scale = Math.min(1, 1200 / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(bitmap.width * scale))
  canvas.height = Math.max(1, Math.round(bitmap.height * scale))

  const context = canvas.getContext('2d')
  if (!context) {
    bitmap.close()
    throw new Error('Your browser could not prepare the image.')
  }

  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()

  const compressedImage = await new Promise((resolve) => {
    canvas.toBlob(resolve, 'image/webp', 0.72)
  })
  if (!compressedImage) {
    throw new Error('Your browser could not compress this image.')
  }
  if (compressedImage.size > MAX_COMPRESSED_IMAGE_SIZE) {
    throw new Error('Compressed image is still too large. Choose a simpler or smaller image.')
  }

  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result ?? ''))
    reader.onerror = () => reject(reader.error ?? new Error('Could not read the image.'))
    reader.readAsDataURL(compressedImage)
  })
}

function normalizeCategory(value) {
  const category = String(value ?? '').trim().toLowerCase()

  if (!category || category === 'uncategorized' || category === 'other') return 'Other'
  if (['laptop', 'laptops', 'notebook', 'notebooks'].includes(category)) return 'Laptop'
  if (['gpu', 'gpus', 'graphics card', 'graphics cards'].includes(category)) return 'GPU'
  if (['cpu', 'cpus', 'processor', 'processors'].includes(category)) return 'CPU'
  if (['storage', 'ssd', 'hdd', 'drive', 'drives'].includes(category)) return 'Storage'
  if (['accessory', 'accessories', 'peripheral', 'peripherals'].includes(category)) {
    return 'Accessories'
  }
  return 'Other'
}

function App() {
  const [user, setUser] = useState(null)
  const [authReady, setAuthReady] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [authError, setAuthError] = useState('')
  const [isSigningIn, setIsSigningIn] = useState(false)
  const [products, setProducts] = useState([])
  const [customerCount, setCustomerCount] = useState(0)
  const [orders, setOrders] = useState([])
  const [cartCount, setCartCount] = useState(0)
  const [databaseErrors, setDatabaseErrors] = useState({})
  const [databaseStatus, setDatabaseStatus] = useState({})
  const [search, setSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('All categories')
  const [isFormOpen, setIsFormOpen] = useState(false)
  const [editingProduct, setEditingProduct] = useState(null)
  const [form, setForm] = useState(blankProduct)
  const [isProcessingImage, setIsProcessingImage] = useState(false)
  const [formError, setFormError] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  const [notice, setNotice] = useState('')

  useEffect(() => {
    return onAuthStateChanged(
      auth,
      (nextUser) => {
        setUser(nextUser)
        setAuthReady(true)
        setAuthError('')
        setDatabaseErrors({})
        setDatabaseStatus({})
      },
      (error) => {
        setAuthError(error.message)
        setAuthReady(true)
        setDatabaseErrors({})
        setDatabaseStatus({})
      },
    )
  }, [])

  useEffect(() => {
    if (!user) return undefined

    let active = true
    const reportError = (path) => (error) => {
      if (!active) return
      setDatabaseErrors((current) => ({ ...current, [path]: error.message }))
      setDatabaseStatus((current) => ({ ...current, [path]: 'error' }))
    }
    const clearError = (path) => {
      if (!active) return
      setDatabaseErrors((current) => {
        if (!(path in current)) return current
        const next = { ...current }
        delete next[path]
        return next
      })
      setDatabaseStatus((current) => ({ ...current, [path]: 'connected' }))
    }
    const productsRef = ref(database, 'products')
    const unsubscribeProducts = onValue(
      productsRef,
      (snapshot) => {
        const value = snapshot.val()
        const nextProducts =
          value && typeof value === 'object'
            ? Object.entries(value).map(([id, product]) => ({
                id,
                ...(product && typeof product === 'object' ? product : {}),
              }))
            : []

        if (!active) return
        setProducts(nextProducts)
        clearError('products')
      },
      reportError('products'),
    )
    const unsubscribeUsers = onValue(
      ref(database, 'profiles'),
      (snapshot) => {
        const value = snapshot.val()
        setCustomerCount(
          value && typeof value === 'object' ? Object.keys(value).length : 0,
        )
        clearError('profiles')
      },
      reportError('profiles'),
    )
    const unsubscribeCarts = onValue(
      ref(database, 'cart'),
      (snapshot) => {
        const value = snapshot.val()
        const nextCartCount =
          value && typeof value === 'object'
            ? Object.values(value).reduce(
                (count, cart) =>
                  count +
                  (cart && typeof cart === 'object'
                    ? Object.keys(cart).length
                    : 0),
                0,
              )
            : 0
        setCartCount(nextCartCount)
        clearError('cart')
      },
      reportError('cart'),
    )
    const unsubscribeOrders = onValue(
      ref(database, 'transactions'),
      (snapshot) => {
        const value = snapshot.val()
        const nextOrders =
          value && typeof value === 'object'
            ? Object.entries(value).flatMap(([userId, userOrders]) =>
                userOrders && typeof userOrders === 'object'
                  ? Object.entries(userOrders).map(([id, order]) => ({
                      id,
                      userId,
                      ...(order && typeof order === 'object' ? order : {}),
                    }))
                  : [],
              )
            : []
        setOrders(nextOrders)
        clearError('transactions')
      },
      reportError('transactions'),
    )

    return () => {
      active = false
      unsubscribeProducts()
      unsubscribeUsers()
      unsubscribeCarts()
      unsubscribeOrders()
    }
  }, [user])

  const errorEntries = Object.entries(databaseErrors)
  const connectionError = errorEntries
    .map(([path, message]) => `/${path}: ${message}`)
    .join(' • ')
  const connection = errorEntries.length
    ? 'error'
    : ['products', 'profiles', 'cart', 'transactions'].every(
          (path) => databaseStatus[path] === 'connected',
        )
      ? 'connected'
      : 'connecting'

  const categories = CATEGORY_OPTIONS

  const filteredProducts = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase()
    return products.filter((product) => {
      const matchesSearch =
        !normalizedSearch ||
        String(product.name ?? '').toLowerCase().includes(normalizedSearch)
      const matchesCategory =
        categoryFilter === 'All categories' ||
        normalizeCategory(product.category) === categoryFilter
      return matchesSearch && matchesCategory
    })
  }, [categoryFilter, products, search])

  const lowStockCount = products.filter(
    (product) => Number(product.stock) <= 5,
  ).length
  const totalSales = orders.reduce(
    (total, order) => total + Number(order.total || 0),
    0,
  )
  const inventoryValue = products.reduce(
    (total, product) =>
      total + Number(product.price || 0) * Number(product.stock || 0),
    0,
  )

  async function handleSignIn(event) {
    event.preventDefault()
    setAuthError('')
    setIsSigningIn(true)
    try {
      await signInWithEmailAndPassword(auth, email.trim(), password)
    } catch (error) {
      const messages = {
        'auth/invalid-email': 'Enter a valid email address.',
        'auth/invalid-credential': 'The email or password is incorrect.',
        'auth/user-not-found': 'The email or password is incorrect.',
        'auth/wrong-password': 'The email or password is incorrect.',
        'auth/operation-not-allowed':
          'Enable Email/Password sign-in in Firebase Authentication.',
        'auth/network-request-failed':
          'Check your internet connection and try again.',
      }
      setAuthError(messages[error.code] || error.message)
    } finally {
      setIsSigningIn(false)
    }
  }

  if (!authReady) {
    return (
      <main className="auth-screen">
        <div className="auth-card">
          <span className="loader" />
          <p>Connecting to Firebase Authentication...</p>
        </div>
      </main>
    )
  }

  if (!user) {
    return (
      <main className="auth-screen">
        <section className="auth-card">
          <div className="brand-mark">S</div>
          <p className="eyebrow">SEBTECH STORE ADMIN</p>
          <h1>Administrator sign in</h1>
          <p className="page-description">
            Sign in with an administrator account created in Firebase
            Authentication.
          </p>
          {authError && (
            <div className="error-banner" role="alert">
              {authError}
            </div>
          )}
          <form onSubmit={handleSignIn}>
            <label className="form-field">
              Email
              <input
                type="email"
                autoComplete="username"
                required
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </label>
            <label className="form-field">
              Password
              <input
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </label>
            <button
              className="primary-button auth-submit"
              type="submit"
              disabled={isSigningIn}
            >
              {isSigningIn ? 'Signing in...' : 'Sign in'}
            </button>
          </form>
          <p className="auth-help">
            Create admin accounts in Firebase Console. Client sign-ups do not
            receive admin access.
          </p>
        </section>
      </main>
    )
  }

  function openCreateForm() {
    setEditingProduct(null)
    setForm(blankProduct)
    setFormError('')
    setIsFormOpen(true)
  }

  function openEditForm(product) {
    setEditingProduct(product)
    setForm({
      name: String(product.name ?? ''),
      category: normalizeCategory(product.category),
      price: String(product.price ?? ''),
      stock: String(product.stock ?? ''),
      image: String(product.image ?? ''),
    })
    setFormError('')
    setIsFormOpen(true)
  }

  function closeForm() {
    if (isSaving) return
    setIsFormOpen(false)
    setFormError('')
  }

  async function saveProduct(event) {
    event.preventDefault()
    const name = form.name.trim()
    const category = form.category.trim()
    const price = Number(form.price)
    const stock = Number(form.stock)

    if (!name) {
      setFormError('Enter a product name.')
      return
    }
    if (!category) {
      setFormError('Enter a category.')
      return
    }
    if (form.price.trim() === '' || !Number.isFinite(price) || price <= 0) {
      setFormError('Enter a valid price greater than zero.')
      return
    }
    if (
      form.stock.trim() === '' ||
      !Number.isInteger(stock) ||
      stock < 0
    ) {
      setFormError('Stock must be a whole number of zero or more.')
      return
    }
    if (form.image.length > 400000) {
      setFormError('Image data is too large for the database. Choose a smaller image.')
      return
    }

    const productId = editingProduct?.id ?? push(ref(database, 'products')).key
    if (!productId) {
      setFormError('Could not create a product ID. Please try again.')
      return
    }

    setIsSaving(true)
    setFormError('')
    try {
      const productData = {
        name,
        category,
        price,
        stock,
        image: form.image.trim(),
        updatedAt: serverTimestamp(),
      }

      if (editingProduct) {
        await update(ref(database, `products/${editingProduct.id}`), productData)
        setNotice(`${name} was updated.`)
      } else {
        await set(ref(database, `products/${productId}`), {
          ...productData,
          createdAt: serverTimestamp(),
        })
        setNotice(`${name} was added.`)
      }
      setIsFormOpen(false)
    } catch (error) {
      setFormError(`Could not save product: ${error.message}`)
    } finally {
      setIsSaving(false)
    }
  }

  async function deleteProduct(product) {
    if (!window.confirm(`Delete "${product.name || 'this product'}"?`)) return

    try {
      await remove(ref(database, `products/${product.id}`))
      setNotice(`${product.name || 'Product'} was deleted.`)
    } catch (error) {
      setNotice(`Could not delete product: ${error.message}`)
    }
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <a className="brand" href="/" aria-label="SEBTECH admin home">
          <span className="brand-mark">S</span>
          <span>
            <strong>SEBTECH</strong>
            <small>STORE ADMIN</small>
          </span>
        </a>

        <div className="nav-caption">WORKSPACE</div>
        <nav className="side-nav" aria-label="Main navigation">
          <a className="nav-item active" href="#products">
            <span className="nav-icon">▤</span>
            Products
            <span className="nav-count">{products.length}</span>
          </a>
        </nav>

        <div className="sidebar-bottom">
          <span className={`connection-dot ${connection}`} />
          <span>
            <strong>
              {connection === 'connected'
                ? 'Database connected'
                : connection === 'error'
                  ? 'Connection issue'
                  : 'Connecting'}
            </strong>
            <small>Firebase Realtime Database</small>
          </span>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <div className="breadcrumb">
            <span>Workspace</span>
            <span className="breadcrumb-divider">/</span>
            <strong>Products</strong>
          </div>
          <div className="topbar-right">
            <span className={`status-pill ${connection}`}>
              <span className={`connection-dot ${connection}`} />
              {connection === 'connected'
                ? 'Live sync on'
                : connection === 'error'
                  ? 'Sync unavailable'
                  : 'Connecting'}
            </span>
            <span className="admin-email">{user.email}</span>
            <button
              type="button"
              className="sign-out-button"
              onClick={() => signOut(auth)}
            >
              Sign out
            </button>
          </div>
        </header>

        <section className="page-content" id="products">
          <div className="page-heading">
            <div>
              <p className="eyebrow">STORE MANAGEMENT</p>
              <h1>Product inventory</h1>
              <p className="page-description">
                Manage your catalog and keep your client app up to date.
              </p>
            </div>
            <button className="primary-button" onClick={openCreateForm}>
              <span aria-hidden="true">+</span>
              Add product
            </button>
          </div>

          {connectionError && (
            <div className="error-banner" role="alert">
              <strong>Firebase connection failed.</strong> {connectionError}
              <span>
                Signed-in admin UID: <code>{user.uid}</code>. Allow this exact UID
                in the published rules for each denied path, and confirm the
                database URL matches both apps.
              </span>
              <button
                type="button"
                className="copy-uid-button"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(user.uid)
                    setNotice('Admin UID copied. Paste it into the rules file.')
                  } catch (error) {
                    setNotice(`Could not copy UID: ${error.message}`)
                  }
                }}
              >
                Copy admin UID
              </button>
            </div>
          )}

          {notice && (
            <div className="notice-banner" role="status">
              <span>{notice}</span>
              <button
                type="button"
                aria-label="Dismiss notification"
                onClick={() => setNotice('')}
              >
                ×
              </button>
            </div>
          )}

          <div className="stats-grid">
            <article className="stat-card">
              <div className="stat-icon blue">▤</div>
              <div>
                <p>Total products</p>
                <strong>{products.length}</strong>
              </div>
              <span className="stat-footnote">In your catalog</span>
            </article>
            <article className="stat-card">
              <div className="stat-icon purple">▦</div>
              <div>
                <p>Items in carts</p>
                <strong>{cartCount}</strong>
              </div>
              <span className="stat-footnote">Live across customer carts</span>
            </article>
            <article className="stat-card">
              <div className="stat-icon orange">♙</div>
              <div>
                <p>Customers</p>
                <strong>{customerCount}</strong>
              </div>
              <span className="stat-footnote">Registered accounts</span>
            </article>
            <article className="stat-card">
              <div className="stat-icon orange">!</div>
              <div>
                <p>Low stock</p>
                <strong>{lowStockCount}</strong>
              </div>
              <span className="stat-footnote">5 items or fewer</span>
            </article>
            <article className="stat-card">
              <div className="stat-icon green">₱</div>
              <div>
                <p>Orders / sales</p>
                <strong>{orders.length} / ₱{totalSales.toLocaleString('en-PH', { minimumFractionDigits: 2 })}</strong>
              </div>
              <span className="stat-footnote">Live customer orders</span>
            </article>
            <article className="stat-card">
              <div className="stat-icon green">₱</div>
              <div>
                <p>Inventory value</p>
                <strong>₱{inventoryValue.toLocaleString('en-PH', { minimumFractionDigits: 2 })}</strong>
              </div>
              <span className="stat-footnote">Based on current stock</span>
            </article>
          </div>

          <section className="catalog-card" aria-label="Product catalog">
            <div className="catalog-heading">
              <div>
                <h2>All products</h2>
                <p>Changes sync to the client app in real time.</p>
              </div>
              <span className="results-count">
                {filteredProducts.length} {filteredProducts.length === 1 ? 'product' : 'products'}
              </span>
            </div>

            <div className="catalog-tools">
              <label className="search-field">
                <span aria-hidden="true">⌕</span>
                <input
                  type="search"
                  placeholder="Search products..."
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
              </label>
              <select
                aria-label="Filter by category"
                value={categoryFilter}
                onChange={(event) => setCategoryFilter(event.target.value)}
              >
                <option>All categories</option>
                {categories.map((category) => (
                  <option key={category}>{category}</option>
                ))}
              </select>
            </div>

            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>PRODUCT</th>
                    <th>CATEGORY</th>
                    <th>PRICE</th>
                    <th>STOCK</th>
                    <th>LAST UPDATED</th>
                    <th aria-label="Actions" />
                  </tr>
                </thead>
                <tbody>
                  {connection === 'connecting' && products.length === 0 ? (
                    <tr>
                      <td colSpan="6" className="table-message">
                        <span className="loader" />
                        Connecting to your product database...
                      </td>
                    </tr>
                  ) : filteredProducts.length === 0 ? (
                    <tr>
                      <td colSpan="6" className="table-message">
                        {search || categoryFilter !== 'All categories'
                          ? 'No products match your search.'
                          : 'No products yet. Add your first product to get started.'}
                      </td>
                    </tr>
                  ) : (
                    filteredProducts.map((product) => {
                      const stock = Number(product.stock || 0)
                      const updatedAt = Number(product.updatedAt)
                      return (
                        <tr key={product.id}>
                          <td>
                            <div className="product-cell">
                              <div className="product-thumbnail">
                                {isImageSource(product.image) ? (
                                  <img
                                    src={product.image}
                                    alt=""
                                    onError={(event) => {
                                      event.currentTarget.style.display = 'none'
                                    }}
                                  />
                                ) : (
                                  String(product.name ?? 'P').slice(0, 1).toUpperCase()
                                )}
                              </div>
                              <div>
                                <strong>{product.name || 'Unnamed product'}</strong>
                                <small>
                                  {String(product.image ?? '').startsWith('data:image/')
                                    ? 'Image stored in database'
                                    : product.image || 'No image filename'}
                                </small>
                              </div>
                            </div>
                          </td>
                          <td>
                            <span className="category-tag">
                              {normalizeCategory(product.category)}
                            </span>
                          </td>
                          <td className="price-cell">
                            ₱{Number(product.price || 0).toLocaleString('en-PH', {
                              minimumFractionDigits: 2,
                            })}
                          </td>
                          <td>
                            <span
                              className={`stock-tag ${
                                stock === 0 ? 'out' : stock <= 5 ? 'low' : 'available'
                              }`}
                            >
                              <span />
                              {stock} {stock === 1 ? 'unit' : 'units'}
                            </span>
                          </td>
                          <td className="date-cell">
                            {Number.isFinite(updatedAt) && updatedAt > 0
                              ? new Date(updatedAt).toLocaleDateString()
                              : '—'}
                          </td>
                          <td>
                            <div className="row-actions">
                              <button
                                type="button"
                                className="icon-button"
                                aria-label={`Edit ${product.name}`}
                                onClick={() => openEditForm(product)}
                              >
                                Edit
                              </button>
                              <button
                                type="button"
                                className="icon-button danger"
                                aria-label={`Delete ${product.name}`}
                                onClick={() => deleteProduct(product)}
                              >
                                Delete
                              </button>
                            </div>
                          </td>
                        </tr>
                      )
                    })
                  )}
                </tbody>
              </table>
            </div>
          </section>

          <section className="catalog-card orders-card" aria-label="Recent orders">
            <div className="catalog-heading">
              <div>
                <h2>Recent orders</h2>
                <p>Customer checkouts synchronized from the client app.</p>
              </div>
              <span className="results-count">{orders.length} total</span>
            </div>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>ORDER</th>
                    <th>CUSTOMER</th>
                    <th>PAYMENT</th>
                    <th>TOTAL</th>
                    <th>STATUS</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.length === 0 ? (
                    <tr>
                      <td colSpan="5" className="table-message">
                        No customer orders yet.
                      </td>
                    </tr>
                  ) : (
                    [...orders].reverse().slice(0, 10).map((order) => (
                      <tr key={`${order.userId}-${order.id}`}>
                        <td className="date-cell">{order.id.slice(-8)}</td>
                        <td>{order.customerName || order.username || 'Customer'}</td>
                        <td>{order.paymentMethod || '—'}</td>
                        <td className="price-cell">
                          ₱{Number(order.total || 0).toLocaleString('en-PH', {
                            minimumFractionDigits: 2,
                          })}
                        </td>
                        <td>
                          <span className="stock-tag available">
                            <span />
                            {order.status || 'Completed'}
                          </span>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </section>

          <footer className="page-footer">
            <span>SEBTECH Store Admin</span>
            <span>Product data is synchronized through Firebase Realtime Database.</span>
          </footer>
        </section>
      </main>

      {isFormOpen && (
        <div
          className="modal-backdrop"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) closeForm()
          }}
        >
          <section
            className="product-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="product-form-title"
          >
            <div className="modal-heading">
              <div>
                <p className="eyebrow">{editingProduct ? 'EDIT CATALOG' : 'NEW CATALOG ITEM'}</p>
                <h2 id="product-form-title">
                  {editingProduct ? 'Update product' : 'Add a product'}
                </h2>
              </div>
              <button
                type="button"
                className="close-button"
                aria-label="Close form"
                onClick={closeForm}
                disabled={isSaving}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveProduct} noValidate>
              <label className="form-field">
                Product name <span>*</span>
                <input
                  autoFocus
                  value={form.name}
                  onChange={(event) => setForm({ ...form, name: event.target.value })}
                  placeholder="e.g. GeForce RTX 4060"
                  maxLength="100"
                />
              </label>
              <label className="form-field">
                Category <span>*</span>
                <select
                  value={form.category}
                  onChange={(event) => setForm({ ...form, category: event.target.value })}
                  required
                >
                  <option value="">Select a category</option>
                  {CATEGORY_OPTIONS.map((category) => (
                    <option key={category} value={category}>
                      {category}
                    </option>
                  ))}
                </select>
              </label>
              <div className="form-row">
                <label className="form-field">
                  Price (₱) <span>*</span>
                  <input
                    type="number"
                    min="0.01"
                    step="0.01"
                    value={form.price}
                    onChange={(event) => setForm({ ...form, price: event.target.value })}
                    placeholder="0.00"
                  />
                </label>
                <label className="form-field">
                  Stock quantity <span>*</span>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    value={form.stock}
                    onChange={(event) => setForm({ ...form, stock: event.target.value })}
                    placeholder="0"
                  />
                </label>
              </div>
              <label className="form-field">
                Product image <small>(optional)</small>
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  disabled={isProcessingImage || isSaving}
                  onChange={async (event) => {
                    const input = event.target
                    const file = input.files?.[0] ?? null
                    input.value = ''
                    if (!file) return
                    if (
                      !['image/jpeg', 'image/png', 'image/webp'].includes(file.type)
                    ) {
                      setFormError('Choose a JPG, PNG, or WebP image.')
                      return
                    }
                    if (file.size > MAX_IMAGE_FILE_SIZE) {
                      setFormError('Image must be 5 MB or smaller.')
                      return
                    }
                    setIsProcessingImage(true)
                    setFormError('')
                    try {
                      const image = await compressImageForDatabase(file)
                      setForm((current) => ({ ...current, image }))
                    } catch (error) {
                      setFormError(error.message)
                    } finally {
                      setIsProcessingImage(false)
                    }
                  }}
                />
                <small className="field-hint">
                  {isProcessingImage
                    ? 'Compressing image...'
                    : 'Choose JPG, PNG, or WebP up to 5 MB. Images are compressed before saving to Realtime Database.'}
                </small>
                {isImageSource(form.image) && (
                  <img
                    className="image-preview"
                    src={form.image}
                    alt="Product preview"
                  />
                )}
                <input
                  value={form.image.startsWith('data:image/') ? '' : form.image}
                  onChange={(event) => setForm({ ...form, image: event.target.value })}
                  placeholder="Or paste an image URL / asset filename"
                  maxLength="2000"
                  aria-label="Existing image URL or asset filename"
                />
                <small className="field-hint">
                  Existing image URL or legacy client asset filename. Compressed images are limited to about 280 KB.
                </small>
              </label>

              {formError && (
                <p className="form-error" role="alert">
                  {formError}
                </p>
              )}
              <div className="modal-actions">
                <button
                  type="button"
                  className="secondary-button"
                  onClick={closeForm}
                  disabled={isSaving || isProcessingImage}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="primary-button"
                  disabled={isSaving || isProcessingImage}
                >
                  {isProcessingImage
                    ? 'Preparing image...'
                    : isSaving
                      ? 'Saving...'
                      : editingProduct
                        ? 'Save changes'
                        : 'Create product'}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  )
}

export default App
