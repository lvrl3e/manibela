import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { apiClient, ApiError } from './apiClient';

export type AdminRole = 'MAIN_ADMIN' | 'ADMIN';

export interface Admin {
  id: string;
  email: string;
  fullName: string;
  role: AdminRole;
  isActive: boolean;
  createdAt: string;
  lastLoginAt: string | null;
}

interface AuthContextValue {
  admin: Admin | null;
  isLoading: boolean;
  /** True for the duration of an explicit logout — see logout()'s own
   * comment. ProtectedRoute reads this to skip its redirect-with-state. */
  isLoggingOut: boolean;
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
  // Set for the duration of an explicit logout so ProtectedRoute's own
  // redirect-on-no-admin sits out — see the comment on logout() below for
  // why that redirect can't be trusted to fire here.
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const navigate = useNavigate();

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
    setIsLoggingOut(false);
    setAdmin(res.admin);
  }

  function logout() {
    localStorage.removeItem('adminToken');
    sessionStorage.removeItem('adminToken');
    // ProtectedRoute's own redirect-on-no-admin stamps the page you were on
    // as `state.from` so LoginPage can send you *back* there — right for
    // "your session expired mid-browse", wrong for an explicit logout,
    // where the next login should always land on the dashboard rather than
    // wherever you happened to be standing when you clicked Log Out. Since
    // that redirect and this one both fire off the same setAdmin(null) and
    // can't be reliably ordered against each other, isLoggingOut tells
    // ProtectedRoute to sit out entirely and let this navigate (no state)
    // be the only one that happens.
    setIsLoggingOut(true);
    navigate('/login', { replace: true });
    setAdmin(null);
  }

  // Any request, anywhere, can discover mid-session that this admin was
  // just deactivated (see requireAuth's own isActive check in the
  // backend) — reacting the same way an explicit logout does is correct
  // here too: the account isn't usable either way. Registered once;
  // `logout`'s only free variables (navigate, the state setters) are
  // stable across renders, so this closure never goes stale.
  useEffect(() => {
    apiClient.onAccountDeactivated(logout);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function refreshAdmin() {
    const res = await apiClient.get<{ admin: Admin }>('/api/admin/me');
    setAdmin(res.admin);
  }

  return (
    <AuthContext.Provider value={{ admin, isLoading, isLoggingOut, login, logout, refreshAdmin }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { admin, isLoading, isLoggingOut } = useAuth();
  const location = useLocation();

  if (isLoading || isLoggingOut) return null;
  if (!admin) return <Navigate to="/login" state={{ from: location }} replace />;
  return <>{children}</>;
}

export { ApiError };
