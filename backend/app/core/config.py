from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://r2v:r2v@db:5432/r2v"
    redis_url: str = "redis://redis:6379/0"

    s3_endpoint_url: str = "http://minio:9000"
    s3_public_endpoint_url: str | None = "http://localhost:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_region: str = "us-east-1"
    s3_bucket_marketplace_models: str = "r2v-marketplace-models"
    s3_bucket_marketplace_thumbs: str = "r2v-marketplace-thumbs"
    s3_bucket_scans_raw: str = "r2v-user-scans-raw"
    s3_bucket_job_outputs: str = "r2v-job-outputs"
    s3_bucket_chat_attachments: str = "r2v-chat-attachments"

    jwt_secret: str = "dev_secret_change_in_prod"
    jwt_issuer: str = "r2v-backend"
    jwt_audience: str = "r2v-client"
    access_token_expires_min: int = 30
    refresh_token_expires_days: int = 30
    verification_code_expires_min: int = 15
    password_reset_expires_min: int = 30

    # Email verification gate. When False, signup/login do NOT require a verified
    # email: signup marks the account verified and returns tokens, and login does
    # not block unverified password accounts. The verification endpoints/screens
    # remain available either way. Safe temporary bypass for production testing.
    require_email_verification: bool = True

    # Outbound email (SMTP). EMAIL_ENABLED gates all sending; when False the email
    # service is a no-op (codes are still created, just not delivered). Real
    # credentials live only in the deployment .env, never in the examples.
    email_enabled: bool = False
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = ""
    smtp_from_name: str = "RealTwoVirtual"
    smtp_use_tls: bool = True

    google_oauth_client_id: str = ""
    google_oauth_client_secret: str = ""
    # Frontend route that finishes the OAuth redirect flow (receives the R2V
    # access/refresh tokens). Documented for deployments; the live redirect_uri
    # is still passed per-request by the frontend.
    frontend_oauth_callback_url: str = ""
    apple_oauth_client_id: str = ""
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""
    microsoft_oauth_client_id: str = ""
    microsoft_oauth_client_secret: str = ""

    stripe_secret_key: str = ""
    stripe_webhook_secret: str = ""
    stripe_success_url: str = "http://localhost:55509/#/billing/success"
    stripe_cancel_url: str = "http://localhost:55509/#/billing/cancel"
    stripe_subscription_price_id: str = ""

    allowed_origins: str = "http://localhost:55509"
    allowed_origin_regex: str = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    env: str = "dev"
    log_level: str = "INFO"

    # Owner-level super admin bootstrap. When SUPER_ADMIN_EMAIL is set, the
    # account is created (or promoted) to role=super_admin on startup. This is
    # the only safe way to mint the first super admin; there is no public signup
    # for it. The password is only used when the account does not yet exist.
    super_admin_email: str = ""
    super_admin_username: str = ""
    super_admin_password: str = ""

    rate_limit_requests: int = 120
    rate_limit_window_seconds: int = 60
    max_upload_bytes: int = 104857600

    # Chat attachments / voice notes
    chat_attachment_max_bytes: int = 25 * 1024 * 1024  # 25 MB for files/images
    chat_voice_max_bytes: int = 10 * 1024 * 1024  # 10 MB for voice notes
    chat_voice_max_seconds: int = 300  # 5 minutes
    chat_attachment_url_expires_s: int = 3600  # presigned GET lifetime

    # ----------------------------------------------------------------- #
    # Modal AI endpoint (prompt/image/voice -> 3D). Single source of truth.
    # MODAL_R2V_ENDPOINT_URL takes precedence over MODAL_API_URL; resolve via
    # the `modal_endpoint_url` property below. Paths match the deployed Modal
    # app contract (POST /generate, POST /image-to-3d, GET /jobs/{id}).
    # ----------------------------------------------------------------- #
    modal_api_url: str = ""
    modal_r2v_endpoint_url: str = ""
    modal_image_to_3d_path: str = "/image-to-3d"
    modal_prompt_to_3d_path: str = "/generate"
    # Optional bearer token if the Modal app enforces R2V_API_TOKEN.
    r2v_api_token: str = ""
    # Default texture behaviour when a request does not specify one.
    modal_default_with_texture: bool = True
    modal_api_timeout_s: int = 900
    modal_download_retry_s: int = 5
    modal_download_max_attempts: int = 30
    modal_download_fallback_max_attempts: int = 6
    # How long (seconds) to poll the Modal async job before giving up.
    modal_poll_timeout_s: int = 1800
    modal_poll_interval_s: int = 5

    # ----------------------------------------------------------------- #
    # Photogrammetry (photos -> 3D). The backend is a proxy/controller: it
    # forwards reconstruction jobs to the deployed Modal photogrammetry app and
    # caches the returned outputs locally. It no longer runs COLMAP/OpenMVS or
    # any local pipeline folder.
    #
    # Modal contract (single source of truth, verified against the live app):
    #   POST /reconstruct  (multipart: files[], texture_mode, no_strict_mask)
    #     -> BLOCKING; returns a binary ZIP of all outputs (OBJ/PLY/GLB + reports)
    #   GET  /logs/{run_id}/{log_name}
    #   GET  /health
    # ----------------------------------------------------------------- #
    photogrammetry_provider: str = "modal"
    photogrammetry_modal_api_url: str = (
        "https://seifh3333--r2v-photogrammetry-pipeline-fastapi-app.modal.run"
    )
    # The reconstruction call is blocking and can take many minutes; allow up to
    # 30 minutes by default before the backend gives up on the Modal request.
    photogrammetry_modal_timeout_s: int = 1800

    # Lifetime (seconds) of the short-lived signed token embedded in
    # photogrammetry download URLs. It lets the headerless GLB preview and file
    # downloads authorize without a bearer header while staying scoped to the
    # owning user + job. Default 6 hours.
    photogrammetry_download_token_expires_s: int = 6 * 60 * 60

    photogrammetry_jobs_root: str = "jobs"
    photogrammetry_texture_mode: str = "vertexcolor"
    photogrammetry_no_strict_mask: bool = False
    photogrammetry_min_images: int = 3
    photogrammetry_max_images: int = 250
    photogrammetry_max_image_bytes: int = 25 * 1024 * 1024

    # Legacy local-pipeline settings. Retained for backwards-compatible env
    # parsing only; the Modal proxy ignores them (no local pipeline is run).
    photogrammetry_pipeline_root: str = "../photogrammetry_pipeline_project"
    photogrammetry_python_exe: str = "python"
    photogrammetry_tools_root: str = ""

    @property
    def modal_endpoint_url(self) -> str:
        """Resolved Modal endpoint: MODAL_R2V_ENDPOINT_URL takes precedence,
        then MODAL_API_URL. Empty string means 'not configured'."""
        return (self.modal_r2v_endpoint_url or self.modal_api_url or "").strip()

    @property
    def is_production(self) -> bool:
        return self.env.strip().lower() in {"prod", "production"}

settings = Settings()
