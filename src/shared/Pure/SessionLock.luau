--!strict
-- Pure session-lock transforms applied inside DataStore UpdateAsync callbacks.
-- Stored record shape: { data: any, lock: { jobId: string, time: number }? , savedAt: number? }
local SessionLock = {}

export type Record = { data: any, lock: { jobId: string, time: number }?, savedAt: number? }

-- Tries to take the lock. Returns (recordToWrite | nil, status).
-- status: "acquired" (new or ours or expired lock stolen) | "locked" (another live server holds it)
function SessionLock.acquire(record: Record?, jobId: string, now: number, ttl: number): (Record?, string)
	local rec: Record = record or { data = nil }
	local lock = rec.lock
	if lock and lock.jobId ~= jobId and now - lock.time < ttl then
		return nil, "locked"
	end
	local status = if lock and lock.jobId ~= jobId then "stolen" else "acquired"
	return { data = rec.data, lock = { jobId = jobId, time = now }, savedAt = rec.savedAt }, status
end

-- Writes data if we still own the lock. `release` clears the lock (player leaving).
-- status: "saved" | "lost" (another server took the lock; do NOT overwrite)
function SessionLock.save(record: Record?, jobId: string, now: number, data: any, release: boolean): (Record?, string)
	local lock = record and record.lock
	if lock and lock.jobId ~= jobId then
		return nil, "lost"
	end
	return {
		data = data,
		lock = if release then nil else { jobId = jobId, time = now },
		savedAt = now,
	}, "saved"
end

return SessionLock
