import { getApp, getApps, initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getDatabase } from 'firebase/database'

const firebaseConfig = {
  apiKey: 'AIzaSyBsjTApqhdLsupQ2OA3lzO8zNXEMrMMch8',
  authDomain: 'product-system-app-8a06e.firebaseapp.com',
  databaseURL: 'https://product-system-app-8a06e-default-rtdb.firebaseio.com',
  projectId: 'product-system-app-8a06e',
  storageBucket: 'product-system-app-8a06e.firebasestorage.app',
  messagingSenderId: '877308315690',
}

const app = getApps().length ? getApp() : initializeApp(firebaseConfig)

export const database = getDatabase(app)
export const auth = getAuth(app)
