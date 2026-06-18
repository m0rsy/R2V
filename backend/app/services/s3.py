from __future__ import annotations
import boto3
from botocore.client import Config
from urllib.parse import urlparse, urlunparse
from app.core.config import settings


def _client_kwargs(endpoint_url: str | None) -> dict:
    """Build boto3 client kwargs that work for BOTH local MinIO and real AWS S3.

    * ``endpoint_url`` is only passed when non-empty. For real AWS S3 the env
      var ``S3_ENDPOINT_URL`` is left empty, so boto3 targets the regional AWS
      endpoint. Passing an empty string here would break boto3.
    * Static credentials are only passed when BOTH access key and secret key are
      provided. On ECS/EC2 these are left empty so boto3 uses the IAM task role
      via its default credential provider chain (never hardcode AWS keys).
    """
    kwargs: dict = {
        "region_name": settings.s3_region,
        "config": Config(signature_version="s3v4"),
    }
    if endpoint_url:
        kwargs["endpoint_url"] = endpoint_url
        # Force path-style addressing for custom endpoints (MinIO). With the
        # default "auto" style, boto3 may switch to virtual-hosted-style
        # (https://<bucket>.files.realtwovirtual.com/...), which has no DNS
        # record or TLS cert behind Caddy and would break presigned URLs.
        # Real AWS S3 (empty endpoint_url) keeps boto3's default addressing.
        kwargs["config"] = Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"},
        )
    if settings.s3_access_key and settings.s3_secret_key:
        kwargs["aws_access_key_id"] = settings.s3_access_key
        kwargs["aws_secret_access_key"] = settings.s3_secret_key
    return kwargs


class S3Client:
    def __init__(self) -> None:
        self.client = boto3.client("s3", **_client_kwargs(settings.s3_endpoint_url))
        self.public_client = None
        if settings.s3_public_endpoint_url:
            self.public_client = boto3.client(
                "s3", **_client_kwargs(settings.s3_public_endpoint_url)
            )

    def _apply_public_endpoint(self, url: str) -> str:
        if not settings.s3_public_endpoint_url:
            return url
        public = urlparse(settings.s3_public_endpoint_url)
        original = urlparse(url)
        if not public.scheme or not public.netloc:
            return url
        public_path = public.path.rstrip("/")
        new_path = f"{public_path}{original.path}" if public_path else original.path
        return urlunparse(
            original._replace(
                scheme=public.scheme,
                netloc=public.netloc,
                path=new_path,
            )
        )

    def presign_put(
        self,
        bucket: str,
        key: str,
        expires: int = 3600,
        content_type: str | None = None,
    ) -> str:
        params = {"Bucket": bucket, "Key": key}
        if content_type:
            params["ContentType"] = content_type
        client = self.public_client or self.client
        return client.generate_presigned_url("put_object", Params=params, ExpiresIn=expires)

    def presign_get(self, bucket: str, key: str, expires: int = 3600) -> str:
        client = self.public_client or self.client
        url = client.generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": key}, ExpiresIn=expires)
        if client is self.client:
            return self._apply_public_endpoint(url)
        return url

    def upload_file(self, local_path: str, bucket: str, key: str, content_type: str | None = None) -> None:
        extra = {"ContentType": content_type} if content_type else {}
        self.client.upload_file(local_path, bucket, key, ExtraArgs=extra)

    def download_file(self, bucket: str, key: str, local_path: str) -> None:
        """Download an object from storage to a local path (used by workers that
        must fetch uploaded inputs before processing)."""
        self.client.download_file(bucket, key, local_path)

    def copy_object(
        self,
        src_bucket: str,
        src_key: str,
        dst_bucket: str,
        dst_key: str,
        content_type: str | None = None,
    ) -> None:
        """Server-side copy of an object between buckets on the same backend
        (MinIO or AWS S3). Used to promote a generated job output into the
        marketplace bucket without streaming bytes through the API. Caller is
        responsible for passing trusted, server-derived keys."""
        params: dict = {
            "Bucket": dst_bucket,
            "Key": dst_key,
            "CopySource": {"Bucket": src_bucket, "Key": src_key},
        }
        if content_type:
            params["ContentType"] = content_type
            params["MetadataDirective"] = "REPLACE"
        self.client.copy_object(**params)

s3 = S3Client()
