import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { apiClient, ApiError } from './apiClient';

export interface Admin {
  id: string;
  email: string;
  fullName: string;
}

interface AuthContextValue {
  admin: Admin | null;
  isLoading: boolean;
  login: (email: string, password: string, rememberMe: boolean) => Promise<void>;
  logout: () => void;
  /** Re-fetches /me — call after PATCH /me so the sidebar/header reflect
   * a just-saved profile change without a full page reload. */
  refreshAdmin: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [admin, setAdmin] = useState<Admin | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem('adminToken') ?? sessionStorage.getItem('adminToken');
    if (!token) {
      setIsLoading(false);
      return;
    }
    apiClient
      .get<{ admin: Admin }>('/api/admin/me')
      .then((res) => setAdmin(res.admin))
      .catch(() => {
        // Stale/expired token — clear it so the login page shows instead
        // of silently retrying on every navigation.
        localStorage.removeItem('adminToken');
        sessionStorage.removeItem('adminToken');
      })
      .finally(() => setIsLoading(false));
  }, []);

  async function login(email: string, password: string, rememberMe: boolean) {
    const res = await apiClient.post<{ token: string; admin: Admin }>('/api/admin/login', {
      email,
      password,
    });
    // "Remember me" persists across browser restarts (localStorage);
    // otherwise the session only lasts the tab (sessionStorage).
    (rememberMe ? localStorage : sessionStorage).setItem('adminToken', res.token);
    setAdmin(res.admin);
  }

  function logout() {
    localStorage.removeItem('adminToken');
    sessionStorage.removeItem('adminToken');
    setAdmin(null);
  }

  async function refreshAdmin() {
    const res = await apiClient.get<{ admin: Admin }>('/api/admin/me');
    setAdmin(res.admin);
  }

  return (
    <AuthContext.Provider value={{ admin, isLoading, login, logout, refreshAdmin }}>{children}</AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { admin, isLoading } = useAuth();
  const location = useLocation();

  if (isLoading) return null;
  if (!admin) return <Navigate to="/login" state={{ from: location }} replace />;
  return <>{children}</>;
}

export { ApiError };
