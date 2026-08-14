import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { AuthProvider, ProtectedRoute } from './lib/auth';
import LoginPage from './pages/LoginPage';
import ForgotPasswordPage from './pages/ForgotPasswordPage';
import DashboardPage from './pages/DashboardPage';
import DriversPage from './pages/DriversPage';
import CommutersPage from './pages/CommutersPage';
import CommuterDetailPage from './pages/CommuterDetailPage';
import IdVerificationPage from './pages/IdVerificationPage';
import JeepneyMonitoringPage from './pages/JeepneyMonitoringPage';
import JeepneyLiveMapPage from './pages/JeepneyLiveMapPage';
import TripHistoryPage from './pages/TripHistoryPage';
import PassengerMonitoringPage from './pages/PassengerMonitoringPage';
import PassengerLiveMapPage from './pages/PassengerLiveMapPage';
import IncidentReportsPage from './pages/IncidentReportsPage';
import ReportsPage from './pages/ReportsPage';
import SettingsPage from './pages/SettingsPage';

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/forgot-password" element={<ForgotPasswordPage />} />

          <Route
            path="/"
            element={
              <ProtectedRoute>
                <DashboardPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/jeepney-monitoring"
            element={
              <ProtectedRoute>
                <JeepneyMonitoringPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/jeepney-monitoring/map"
            element={
              <ProtectedRoute>
                <JeepneyLiveMapPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/jeepney-monitoring/history"
            element={
              <ProtectedRoute>
                <TripHistoryPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/passenger-monitoring"
            element={
              <ProtectedRoute>
                <PassengerMonitoringPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/passenger-monitoring/map"
            element={
              <ProtectedRoute>
                <PassengerLiveMapPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/drivers"
            element={
              <ProtectedRoute>
                <DriversPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/commuters"
            element={
              <ProtectedRoute>
                <CommutersPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/commuters/:id"
            element={
              <ProtectedRoute>
                <CommuterDetailPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/id-verification"
            element={
              <ProtectedRoute>
                <IdVerificationPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/incident-reports"
            element={
              <ProtectedRoute>
                <IncidentReportsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/reports"
            element={
              <ProtectedRoute>
                <ReportsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/settings"
            element={
              <ProtectedRoute>
                <SettingsPage />
              </ProtectedRoute>
            }
          />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
