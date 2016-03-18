<#
    .SYNOPSIS PowerShell module for GitHub analytics
#>

$apiTokensFilePath = "$PSScriptRoot\ApiTokens.psm1"
if (Test-Path $apiTokensFilePath)
{
    Write-Host "Importing $apiTokensFilePath"
    Import-Module  -force $apiTokensFilePath
}
else
{
    Write-Host "$apiTokensFilePath does not exist, skipping import"
    Write-Host @'
# This module should define $global:gitHubApiToken with your GitHub API access token. Create this file it if it doesn't exist.
# You can get GitHub token from https://github.com/settings/tokens
# If you don't provide it, you can still use this module, but you will be limited to 60 queries per hour.
'@
}

$script:gitHubToken = $global:gitHubApiToken 
$script:gitHubApiUrl = "https://api.github.com"
$script:gitHubApiReposUrl = "https://api.github.com/repos"
$script:gitHubApiOrgsUrl = "https://api.github.com/orgs"
$script:maxPageSize = 100

<#
    .SYNOPSIS Function which gets list of issues for given repository
    .PARAM
        repositoryUrl Array of repository urls which we want to get issues from
    .PARAM 
        state Whether we want to get open, closed or all issues
    .PARAM
        createdOnOrAfter Filter to only get issues created on or after specific date
    .PARAM
        createdOnOrBefore Filter to only get issues created on or before specific date    
    .PARAM
        closedOnOrAfter Filter to only get issues closed on or after specific date
    .PARAM
        ClosedOnOrBefore Filter to only get issues closed on or before specific date
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE
        $issues = Get-GitHubIssuesForRepository -repositoryUrl @('https://github.com/PowerShell/xPSDesiredStateConfiguration')
    .EXAMPLE
        $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl @('https://github.com/PowerShell/xPSDesiredStateConfiguration', "https://github.com/PowerShell/xWindowsUpdate" ) `
            -createdOnOrAfter '2015-04-20'
#>
function Get-GitHubIssuesForRepository
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        [ValidateSet("open", "closed", "all")]
        [String] $state = "open",
        [DateTime] $createdOnOrAfter,
        [DateTime] $createdOnOrBefore,
        [DateTime] $closedOnOrAfter,
        [DateTime] $closedOnOrBefore,
        $gitHubAccessToken = $script:gitHubToken
    )

    $resultToReturn = @()

    $index = 0
    
    foreach ($repository in $repositoryUrl)
    {
        Write-Host "Getting issues for repository $repository" -ForegroundColor Yellow

        $repositoryName = Get-GitHubRepositoryNameFromUrl -repositoryUrl $repository
        $repositoryOwner = Get-GitHubRepositoryOwnerFromUrl -repositoryUrl $repository

        # Create query for issues
        $query = "$script:gitHubApiReposUrl/$repositoryOwner/$repositoryName/issues?state=$state"
            
        if (![string]::IsNullOrEmpty($gitHubAccessToken))
        {
            $query += "&access_token=$gitHubAccessToken"
        }
        
        # Obtain issues    
        $jsonResult = Invoke-WebRequest $query
        $issues = ConvertFrom-Json -InputObject $jsonResult.content
        
        foreach ($issue in $issues)
        {
            # GitHub considers pull request to be an issue, so let's skip pull requests.
            if ($issue.pull_request -ne $null)
            {
                continue
            }

            # Filter according to createdOnOrAfter
            $createdDate = Get-Date -Date $issue.created_at
            if (($createdOnOrAfter -ne $null) -and ($createdDate -lt $createdOnOrAfter))
            {
                continue  
            }

            # Filter according to createdOnOrBefore
            if (($createdOnOrBefore -ne $null) -and ($createdDate -gt $createdOnOrBefore))
            {
                continue  
            }

            if ($issue.closed_at -ne $null)
            {
                # Filter according to closedOnOrAfter
                $closedDate = Get-Date -Date $issue.closed_at
                if (($closedOnOrAfter -ne $null) -and ($closedDate -lt $closedOnOrAfter))
                {
                    continue  
                }

                # Filter according to closedOnOrBefore
                if (($closedOnOrBefore -ne $null) -and ($closedDate -gt $closedOnOrBefore))
                {
                    continue  
                }
            }
            else
            {
                # If issue isn't closed, but we specified filtering on closedOn, skip it
                if (($closedOnOrAfter -ne $null) -or ($closedOnOrBefore -ne $null))
                {
                    continue
                }
            }
            
            Write-Host "$index. $($issue.html_url) ## Created: $($issue.created_at) ## Closed: $($issue.closed_at)"
            $index++

            $resultToReturn += $issue
        }
    }

    return $resultToReturn
}

<#
    .SYNOPSIS Function which returns number of issues created/merged in every week in specific repositories
    .PARAM
        repositoryUrl Array of repository urls which we want to get pull requests from
    .PARAM 
        numberOfWeeks How many weeks we want to obtain data for
    .PARAM 
        dataType Whether we want to get information about created or merged issues in specific weeks
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE
        Get-GitHubWeeklyIssuesForRepository -repositoryUrl @('https://github.com/powershell/xpsdesiredstateconfiguration', 'https://github.com/powershell/xactivedirectory') -datatype closed

#>
function Get-GitHubWeeklyIssuesForRepository
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        [int] $numberOfWeeks = 12,
        [Parameter(Mandatory=$true)]
        [ValidateSet("created","closed")]
        [string] $dataType,
        $gitHubAccessToken = $script:gitHubToken
    )

    $weekDates = Get-WeekDates -numberOfWeeks $numberOfWeeks
    $endOfWeek = Get-Date
    $results = @()
    $totalIssues = 0

    foreach ($week in $weekDates)
    {
        Write-Host "Getting issues from week of $week"

        $issues = $null

        if ($dataType -eq "closed")
        {
            $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl $repositoryUrl -state 'all' -closedOnOrAfter $week -closedOnOrBefore $endOfWeek    
        }
        elseif ($dataType -eq "created")
        {
            $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl $repositoryUrl -state 'all' -createdOnOrAfter $week -createdOnOrBefore $endOfWeek
        }
        
        $endOfWeek = $week
        
        if (($issues -ne $null) -and ($issues.Count -eq $null))
        {
            $count = 1
        }
        else
        {
            $count = $issues.Count
        }
        
        $totalIssues += $count

        $results += @{"BeginningOfWeek"=$week; "Issues"=$count}
    }

    $results += @{"BeginningOfWeek"="total"; "Issues"=$totalIssues}
    return $results    
}

<#
    .SYNOPSIS Function which returns repositories with biggest number of issues meeting specified criteria
    .PARAM
        repositoryUrl Array of repository urls which we want to get issues from
    .PARAM 
        state Whether we want to get information about open issues, closed or both
    .PARAM
        createdOnOrAfter Get information about issues created after specific date
    .PARAM
        closedOnOrAfter Get information about issues closed after specific date
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE
        Get-GitHubTopIssuesRepository -repositoryUrl @('https://github.com/powershell/xsharepoint', 'https://github.com/powershell/xCertificate', 'https://github.com/powershell/xwebadministration') -state open

#>
function Get-GitHubTopIssuesRepository
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        [ValidateSet("open", "closed", "all")]
        [String] $state = "open",
        [DateTime] $createdOnOrAfter,
        [DateTime] $closedOnOrAfter,
        $gitHubAccessToken = $script:gitHubToken
    )
    
    if (($state -eq "open") -and ($closedOnOrAfter -ne $null))
    {
        Throw "closedOnOrAfter cannot be specified if state is open"
    }

    $repositoryIssues = @{}

    foreach ($repository in $repositoryUrl)
    {
        if (($closedOnOrAfter -ne $null) -and ($createdOnOrAfter -ne $null))
        {
            $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl $repository `
            -state $state -closedOnOrAfter $closedOnOrAfter -createdOnOrAfter $createdOnOrAfter
        }
        elseif (($closedOnOrAfter -ne $null) -and ($createdOnOrAfter -eq $null))
        {
            $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl $repository `
            -state $state -closedOnOrAfter $closedOnOrAfter
        }
        elseif (($closedOnOrAfter -eq $null) -and ($createdOnOrAfter -ne $null))
        {
            $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl $repository `
            -state $state -createdOnOrAfter $createdOnOrAfter
        }
        elseif (($closedOnOrAfter -eq $null) -and ($createdOnOrAfter -eq $null))
        {
            $issues = Get-GitHubIssuesForRepository `
            -repositoryUrl $repository `
            -state $state
        }

        if (($issues -ne $null) -and ($issues.Count -eq $null))
        {
            $count = 1
        }
        else
        {
            $count = $issues.Count
        }

        $repositoryName = Get-GitHubRepositoryNameFromUrl -repositoryUrl $repository
        $repositoryIssues.Add($repositoryName, $count)
    }

    $repositoryIssues = $repositoryIssues.GetEnumerator() | Sort-Object Value -Descending

    return $repositoryIssues
}

<#
    .SYNOPSIS Function which gets list of pull requests for given repository
    .PARAM
        repositoryUrl Array of repository urls which we want to get pull requests from
    .PARAM 
        state Whether we want to get open, closed or all pull requests
    .PARAM
        createdOnOrAfter Filter to only get pull requests created on or after specific date
    .PARAM
        createdOnOrBefore Filter to only get pull requests created on or before specific date    
    .PARAM
        mergedOnOrAfter Filter to only get issues merged on or after specific date
    .PARAM
        mergedOnOrBefore Filter to only get issues merged on or before specific date
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE
        $pullRequests = Get-GitHubPullRequestsForRepository -repositoryUrl @('https://github.com/PowerShell/xPSDesiredStateConfiguration')
    .EXAMPLE
        $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl @('https://github.com/PowerShell/xPSDesiredStateConfiguration', 'https://github.com/PowerShell/xWebAdministration') `
            -state closed -mergedOnOrAfter 2015-02-13 -mergedOnOrBefore 2015-06-17

#>
function Get-GitHubPullRequestsForRepository
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        [ValidateSet("open", "closed", "all")]
        [String] $state = "open",
        [DateTime] $createdOnOrAfter,
        [DateTime] $createdOnOrBefore,
        [DateTime] $mergedOnOrAfter,
        [DateTime] $mergedOnOrBefore,
        $gitHubAccessToken = $script:gitHubToken
    )

    $resultToReturn = @()

    $index = 0
    
    foreach ($repository in $repositoryUrl)
    {
        Write-Host "Getting pull requests for repository $repository" -ForegroundColor Yellow

        $repositoryName = Get-GitHubRepositoryNameFromUrl -repositoryUrl $repository
        $repositoryOwner = Get-GitHubRepositoryOwnerFromUrl -repositoryUrl $repository

        # Create query for pull requests
        $query = "$script:gitHubApiReposUrl/$repositoryOwner/$repositoryName/pulls?state=$state"
            
        if (![string]::IsNullOrEmpty($gitHubAccessToken))
        {
            $query += "&access_token=$gitHubAccessToken"
        }
        
        # Obtain pull requests
        $jsonResult = Invoke-WebRequest $query
        $pullRequests = ConvertFrom-Json -InputObject $jsonResult.content

        foreach ($pullRequest in $pullRequests)
        {
            # Filter according to createdOnOrAfter
            $createdDate = Get-Date -Date $pullRequest.created_at
            if (($createdOnOrAfter -ne $null) -and ($createdDate -lt $createdOnOrAfter))
            {
                continue  
            }

            # Filter according to createdOnOrBefore
            if (($createdOnOrBefore -ne $null) -and ($createdDate -gt $createdOnOrBefore))
            {
                continue  
            }

            if ($pullRequest.merged_at -ne $null)
            {
                # Filter according to mergedOnOrAfter
                $mergedDate = Get-Date -Date $pullRequest.merged_at
                if (($mergedOnOrAfter -ne $null) -and ($mergedDate -lt $mergedOnOrAfter))
                {
                    continue
                }

                # Filter according to mergedOnOrBefore
                if (($mergedOnOrBefore -ne $null) -and ($mergedDate -gt $mergedOnOrBefore))
                {
                    continue  
                }
            }
            else
            {
                # If issue isn't merged, but we specified filtering on mergedOn, skip it
                if (($mergedOnOrAfter -ne $null) -or ($mergedOnOrBefore -ne $null))
                {
                    continue
                }
            }
            
            Write-Host "$index. $($pullRequest.html_url) ## Created: $($pullRequest.created_at) ## Merged: $($pullRequest.merged_at)"
            $index++

            $resultToReturn += $pullRequest
        }
    }

    return $resultToReturn
}

<#
    .SYNOPSIS Function which returns number of pull requests created/merged in every week in specific repositories
    .PARAM
        repositoryUrl Array of repository urls which we want to get pull requests from
    .PARAM 
        numberOfWeeks How many weeks we want to obtain data for
    .PARAM 
        dataType Whether we want to get information about created or merged pull requests in specific weeks
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE
        Get-GitHubWeeklyPullRequestsForRepository -repositoryUrl @('https://github.com/powershell/xpsdesiredstateconfiguration', 'https://github.com/powershell/xwebadministration') -datatype merged

#>
function Get-GitHubWeeklyPullRequestsForRepository
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        [int] $numberOfWeeks = 12,
        [Parameter(Mandatory=$true)]
        [ValidateSet("created","merged")]
        [string] $dataType,
        $gitHubAccessToken = $script:gitHubToken
    )
    
    $weekDates = Get-WeekDates -numberOfWeeks $numberOfWeeks
    $endOfWeek = Get-Date
    $results = @()
    $totalPullRequests = 0

    foreach ($week in $weekDates)
    {
        Write-Host "Getting Pull Requests from week of $week"

        $pullRequests = $null

        if ($dataType -eq "merged")
        {
            $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl $repositoryUrl `
            -state 'all' -mergedOnOrAfter $week -mergedOnOrBefore $endOfWeek
        }
        elseif ($dataType -eq "created")
        {
            $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl $repositoryUrl `
            -state 'all' -createdOnOrAfter $week -createdOnOrBefore $endOfWeek
        }
        
        
        $endOfWeek = $week
        

        if (($pullRequests -ne $null) -and ($pullRequests.Count -eq $null))
        {
            $count = 1
        }
        else
        {
            $count = $pullRequests.Count
        }
        $totalPullRequests += $count

        $results += @{"BeginningOfWeek"=$week; "PullRequests"=$count}
    }

    $results += @{"BeginningOfWeek"="total"; "PullRequests"=$totalPullRequests}
    return $results    
}

<#
    .SYNOPSIS Function which returns repositories with biggest number of pull requests meeting specified criteria
    .PARAM
        repositoryUrl Array of repository urls which we want to get pull requests from
    .PARAM 
        state Whether we want to get information about open pull requests, closed or both
    .PARAM
        createdOnOrAfter Get information about pull requests created after specific date
    .PARAM
        mergedOnOrAfter Get information about pull requests merged after specific date
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE
        Get-GitHubTopPullRequestsRepository -repositoryUrl @('https://github.com/powershell/xsharepoint', 'https://github.com/powershell/xwebadministration') -state closed -mergedOnOrAfter 2015-04-20

#>
function Get-GitHubTopPullRequestsRepository
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        [ValidateSet("open", "closed", "all")]
        [String] $state = "open",
        [DateTime] $createdOnOrAfter,
        [DateTime] $mergedOnOrAfter,
        $gitHubAccessToken = $script:gitHubToken
    )
    
    if (($state -eq "open") -and ($mergedOnOrAfter -ne $null))
    {
        Throw "mergedOnOrAfter cannot be specified if state is open"
    }

    $repositoryPullRequests = @{}

    foreach ($repository in $repositoryUrl)
    {
        if (($mergedOnOrAfter -ne $null) -and ($createdOnOrAfter -ne $null))
        {
            $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl $repository `
            -state $state -mergedOnOrAfter $mergedOnOrAfter -createdOnOrAfter $createdOnOrAfter
        }
        elseif (($mergedOnOrAfter -ne $null) -and ($createdOnOrAfter -eq $null))
        {
            $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl $repository `
            -state $state -mergedOnOrAfter $mergedOnOrAfter
        }
        elseif (($mergedOnOrAfter -eq $null) -and ($createdOnOrAfter -ne $null))
        {
            $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl $repository `
            -state $state -createdOnOrAfter $createdOnOrAfter
        }
        elseif (($mergedOnOrAfter -eq $null) -and ($createdOnOrAfter -eq $null))
        {
            $pullRequests = Get-GitHubPullRequestsForRepository `
            -repositoryUrl $repository `
            -state $state
        }

        if (($pullRequests -ne $null) -and ($pullRequests.Count -eq $null))
        {
            $count = 1
        }
        else
        {
            $count = $pullRequests.Count
        }

        $repositoryName = Get-GitHubRepositoryNameFromUrl -repositoryUrl $repository
        $repositoryPullRequests.Add($repositoryName, $count)
    }

    $repositoryPullRequests = $repositoryPullRequests.GetEnumerator() | Sort-Object Value -Descending

    return $repositoryPullRequests
}

<#
    .SYNOPSIS Obtain repository collaborators

    .EXAMPLE $collaborators = Get-GitHubRepositoryCollaborators -repositoryUrl @('https://github.com/PowerShell/DscResources')
#>
function Get-GitHubRepositoryCollaborators
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        $gitHubAccessToken = $script:gitHubToken
    )

    $resultToReturn = @()
    
    foreach ($repository in $repositoryUrl)
    {
        $index = 0
        Write-Host "Getting repository collaborators for repository $repository" -ForegroundColor Yellow

        $repositoryName = Get-GitHubRepositoryNameFromUrl -repositoryUrl $repository
        $repositoryOwner = Get-GitHubRepositoryOwnerFromUrl -repositoryUrl $repository

        $query = "$script:gitHubApiReposUrl/$repositoryOwner/$repositoryName/collaborators"
            
        if (![string]::IsNullOrEmpty($gitHubAccessToken))
        {
            $query += "?access_token=$gitHubAccessToken"
        }
        
        # Obtain all issues    
        $jsonResult = Invoke-WebRequest $query
        $collaborators = ConvertFrom-Json -InputObject $jsonResult.content

        foreach ($collaborator in $collaborators)
        {          
            Write-Host "$index. $($collaborator.login)"
            $index++

            $resultToReturn += $collaborator
        }
    }

    return $resultToReturn
}

<#
    .SYNOPSIS Obtain repository contributors

    .EXAMPLE $contributors = Get-GitHubRepositoryContributors -repositoryUrl @('https://github.com/PowerShell/DscResources', 'https://github.com/PowerShell/xWebAdministration')
#>
function Get-GitHubRepositoryContributors
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]] $repositoryUrl,
        $gitHubAccessToken = $script:gitHubToken
    )

    $resultToReturn = @()
    
    foreach ($repository in $repositoryUrl)
    {
        $index = 0
        Write-Host "Getting repository contributors for repository $repository" -ForegroundColor Yellow

        $repositoryName = Get-GitHubRepositoryNameFromUrl -repositoryUrl $repository
        $repositoryOwner = Get-GitHubRepositoryOwnerFromUrl -repositoryUrl $repository

        $query = "$script:gitHubApiReposUrl/$repositoryOwner/$repositoryName/stats/contributors"
            
        if (![string]::IsNullOrEmpty($gitHubAccessToken))
        {
            $query += "?access_token=$gitHubAccessToken"
        }
        
        # Obtain all issues    
        $jsonResult = Invoke-WebRequest $query
        $contributors = ConvertFrom-Json -InputObject $jsonResult.content

        foreach ($contributor in $contributors)
        {          
            Write-Host "$index. $($contributor.author.login) ## Commits: $($contributor.total)"
            $index++

            $resultToReturn += $contributor
        }
    }

    return $resultToReturn
}

<#
    .SYNOPSIS Obtain organization members list
    .PARAM 
        organizationName name of the organization
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.

    .EXAMPLE $members = Get-GitHubOrganizationMembers -organizationName PowerShell
#>
function Get-GitHubOrganizationMembers
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String] $organizationName,
        $gitHubAccessToken = $script:gitHubToken
    )

    $query = "$script:gitHubApiOrgsUrl/$organizationName/members?per_page=$maxPageSize"
        
    if (![string]::IsNullOrEmpty($gitHubAccessToken))
    {
        $query += "&access_token=$gitHubAccessToken"
    }
    
    $jsonResult = Invoke-WebRequest $query
    $members = ConvertFrom-Json -InputObject $jsonResult.content

    if ($members.Count -eq $maxPageSize)
    {
        Write-Warning "We hit the limit of $maxPageSize per page. This function currently does not support pagination."
    }

    return $members
}

<#
    .SYNOPSIS Obtain organization teams list
    .PARAM 
        organizationName name of the organization
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.
    .EXAMPLE Get-GitHubTeams -organizationName PowerShell
#>
function Get-GitHubTeams
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String] $organizationName,
        $gitHubAccessToken = $script:gitHubToken
    )

    $query = "$script:gitHubApiUrl/orgs/$organizationName/teams?per_page=$maxPageSize"
        
    if (![string]::IsNullOrEmpty($gitHubAccessToken))
    {
        $query += "&access_token=$gitHubAccessToken"
    }
    
    $jsonResult = Invoke-WebRequest $query
    $teams = ConvertFrom-Json -InputObject $jsonResult.content

    if ($teams.Count -eq $maxPageSize)
    {
        Write-Warning "We hit the limit of $maxPageSize per page. This function currently does not support pagination."
    }

    return $teams
}

<#
    .SYNOPSIS Obtain organization team members list
    .PARAM 
        organizationName name of the organization
    .PARAM 
        teamName name of the team in the organization
    .PARAM
        gitHubAccessToken GitHub API Access Token.
            Get github token from https://github.com/settings/tokens 
            If you don't provide it, you can still use this script, but you will be limited to 60 queries per hour.

    .EXAMPLE $members = Get-GitHubTeamMembers -organizationName PowerShell -teamName Everybody
#>
function Get-GitHubTeamMembers
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String] $organizationName,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String] $teamName,
        $gitHubAccessToken = $script:gitHubToken
    )

    $teams = Get-GitHubTeams -organizationName $organizationName
    $team = $teams | ? {$_.name -eq $teamName}
    if ($team) {
        Write-Host "Found team $teamName with id $($team.id)"
    } else {
        Write-Host "Cannot find team $teamName"
        return
    }

    $query = "$script:gitHubApiUrl/teams/$($team.id)/members?per_page=$maxPageSize"
        
    if (![string]::IsNullOrEmpty($gitHubAccessToken))
    {
        $query += "&access_token=$gitHubAccessToken"
    }
    
    $jsonResult = Invoke-WebRequest $query
    $members = ConvertFrom-Json -InputObject $jsonResult.content

    if ($members.Count -eq $maxPageSize)
    {
        Write-Warning "We hit the limit of $maxPageSize per page. This function currently does not support pagination."
    }

    return $members
}

<#
    .SYNOPSIS Returns array of unique contributors which were contributing to given set of repositories. Accepts output of Get-GitHubRepositoryContributors

    .EXAMPLE $contributors = Get-GitHubRepositoryContributors -repositoryUrl @('https://github.com/PowerShell/DscResources', 'https://github.com/PowerShell/xWebAdministration')
             $uniqueContributors = Get-GitHubRepositoryUniqueContributors -contributors $contributors
#>
function Get-GitHubRepositoryUniqueContributors
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]] $contributors
    )

    $uniqueContributors = @()
    
    Write-Host "Getting unique repository contributors" -ForegroundColor Yellow

    foreach ($contributor in $contributors)
    {
        if (-not $uniqueContributors.Contains($contributor.author.login))
        {
            $uniqueContributors += $contributor.author.login
        }
    }

    return $uniqueContributors
}