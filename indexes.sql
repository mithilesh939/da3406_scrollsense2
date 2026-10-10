CREATE INDEX IF NOT EXISTS idx_video_audio_uploaded ON Video(audio_track_id, uploaded_at);

CREATE INDEX IF NOT EXISTS idx_like_retracted_cover ON Like_(retracted_at, liked_at, user_id, video_id);

CREATE INDEX IF NOT EXISTS idx_impression_video_user ON Impression(video_id, user_id);
