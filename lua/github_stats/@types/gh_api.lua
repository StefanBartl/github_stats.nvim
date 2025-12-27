---@module 'github_stats.@types.gh_api'

---@class GHStats.GithubApiClone
---@field timestamp string ISO 8601 timestamp
---@field count integer Total clones
---@field uniques integer Unique cloners

---@class GHStats.GithubApiClonesResponse
---@field count integer Total clones over period
---@field uniques integer Total unique cloners
---@field clones GHStats.GithubApiClone[] Daily breakdown

---@class GHStats.GithubApiView
---@field timestamp string ISO 8601 timestamp
---@field count integer Total views
---@field uniques integer Unique visitors

---@class GHStats.GithubApiViewsResponse
---@field count integer Total views over period
---@field uniques integer Total unique visitors
---@field views GHStats.GithubApiView[] Daily breakdown

---@class GHStats.GithubApiReferrer
---@field referrer string Referrer domain/path
---@field count integer Number of referrals
---@field uniques integer Unique referrers

---@class GHStats.GithubApiPath
---@field path string Repository path
---@field title string Page title
---@field count integer Number of views
---@field uniques integer Unique visitors

---@class GHStats.StoredMetricData
---@field timestamp string When data was fetched
---@field data GHStats.GithubApiClonesResponse|GHStats.GithubApiViewsResponse|GHStats.GithubApiReferrer[]|GHStats.GithubApiPath[] Raw API response

return {}
