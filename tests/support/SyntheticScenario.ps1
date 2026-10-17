# A made-up Dev and Test on Microsoft's real Contact Center schema (tests/fixtures/schema.json),
# small enough to reason about and covering every case the engine has to get right. GUIDs differ
# per org, as they do in real environments.
#
#   Dev (source)                                   Test (target)
#   ------------------------------------------     ------------------------------------------
#   Office hours                                   Office hours                    Equal
#   skill Billing, skill Mortgages                 skill Billing                   Mortgages new
#   capacity Default; Chat capacity x2             Default; Chat capacity (a)      tie-breaker
#     (cap_chat_a, cap_chat_b)                                                     pairs a, b new
#   session msdyn_chat_session, contoso_mortgage   msdyn_chat_session              mortgage new
#   notification contoso_mortgage_notification     -                               new
#   notification msdyn_chatgpt_notification        -                               managed: blocks
#     (managed)                                                                    GPT chat
#   workstream Billing chat (capacity 2)           Billing chat (capacity 1)       Changed
#   workstream Mortgage chat (templates, default   -                               new, with links
#     queue + routing contract linked later)                                       at the end
#   workstream GPT chat (managed template)         -                               blocked
#   context variable CustomerTier on Mortgage      -                               new
#   Mortgage chat uses capacity Default            -                               new link record
#   queue Billing queue, Mortgage queue,           Billing queue                   Mortgage new;
#     personal queue Peter                                                         personal ignored
#   contract billing (v2), mortgage                contract billing (v1)           create-once:
#                                                                                  billing skipped
#   ruleset billing route (embeds Billing queue)   billing route (its own GUID)    Equal
#   ruleset mortgage route (embeds Mortgage        -                               new, GUIDs
#     queue and skill Mortgages)                                                   rewritten
#   routing config under Billing chat              same                            Equal
#     step Route to queue -> billing route           step Route to queue -> none   Changed
#   routing config + step under Mortgage chat      -                               new
#   WhatsApp number on Mortgage chat               -                               needs account
#   quick reply Greeting                           -                               new, no deps
#   tags VIP x2 (identical), Escalated             tag Old tag                     VIP one record,
#                                                                                  Old tag extra
#   operating hours Weekend x2 (different)         -                               Ambiguous
#   Omnichannel configuration (3 declines)         same (1 decline)                Changed
#   Greeting on Mortgage chat and Billing chat,    -                               3 links new
#     tagged Escalated (many-to-many links)

function Get-CcSchemaFixture {
    $path = Join-Path $PSScriptRoot '../fixtures/schema.json'
    $raw = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
    # Back to the shape a Web API read returns.
    $m = @{}
    foreach ($k in $raw.Keys) { $m[$k] = if ($raw[$k]) { $raw[$k] | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json } else { $null } }
    return $m
}

function New-CcSyntheticScenario {
    param([switch] $ProvisionRoutingConfiguration)
    $schema = Get-CcSchemaFixture
    $dev = New-CcFakeOrg -Url 'https://contoso-dev.crm4.dynamics.com' -Metadata $schema
    $test = New-CcFakeOrg -Url 'https://contoso-test.crm4.dynamics.com' -Metadata $schema -ProvisionRoutingConfiguration:$ProvisionRoutingConfiguration
    $ids = @{ dev = @{}; test = @{} }

    $chat = @{ msdyn_mode = 192350000; msdyn_streamsource = 192360000; msdyn_direction = 192350000; msdyn_workdistributionmode = 192350000 }

    foreach ($side in 'dev', 'test') {
        $o = if ($side -eq 'dev') { $dev } else { $test }
        $i = $ids[$side]
        $i.english = Add-CcFakeRecord $o msdyn_oclanguage @{ msdyn_languagename = 'English'; msdyn_localeid = 1033 }
        $i.hours = Add-CcFakeRecord $o msdyn_operatinghour @{ msdyn_name = 'Office hours' }
        $i.skillBilling = Add-CcFakeRecord $o characteristic @{ name = 'Billing'; characteristictype = 1 }
        $i.capDefault = Add-CcFakeRecord $o msdyn_capacityprofile @{ msdyn_name = 'Default'; msdyn_uniquename = 'default_profile'; msdyn_defaultmaxunits = 100; msdyn_blockassignment = $false }
        $i.capChatA = Add-CcFakeRecord $o msdyn_capacityprofile @{ msdyn_name = 'Chat capacity'; msdyn_uniquename = 'cap_chat_a'; msdyn_defaultmaxunits = 2; msdyn_blockassignment = $false }
        $i.session = Add-CcFakeRecord $o msdyn_sessiontemplate @{ msdyn_name = 'Chat session'; msdyn_uniquename = 'msdyn_chat_session'; msdyn_title = 'Chat' }
        $i.billingQueue = Add-CcFakeRecord $o queue @{ name = 'Billing queue'; msdyn_queuetype = 192350000; msdyn_isomnichannelqueue = $true; msdyn_priority = 1 } @{ msdyn_operatinghourid = $i.hours }
        $i.billingContract = Add-CcFakeRecord $o msdyn_decisioncontract @{ msdyn_name = 'Billing contract'; msdyn_uniquename = 'contoso_billing_contract'; msdyn_contractdefinition = $(if ($side -eq 'dev') { '{"v":2}' } else { '{"v":1}' }) }
        $i.billingRoute = Add-CcFakeRecord $o msdyn_decisionruleset @{
            msdyn_name = 'Billing route'; msdyn_uniquename = 'contoso_billing_route'
            msdyn_rulesetdefinition = "<rules><rule queue=`"$($i.billingQueue)`" skill=`"$($i.skillBilling.ToUpperInvariant())`"/></rules>"
        }
        $i.billingChat = Add-CcFakeRecord $o msdyn_liveworkstream ($chat + @{
                msdyn_name = 'Billing chat'; msdyn_capacityrequired = $(if ($side -eq 'dev') { 2 } else { 1 })
                msdyn_sessiontemplate_default = 'msdyn_chat_session'
            }) @{ msdyn_defaultqueue = $i.billingQueue }
        $i.billingRc = Add-CcFakeRecord $o msdyn_routingconfiguration @{ msdyn_name = 'Contact center routing configuration'; msdyn_uniquename = 'rc_billing'; msdyn_isactiveconfiguration = $true } @{ msdyn_liveworkstreamid = $i.billingChat }
        $stepLookups = if ($side -eq 'dev') { @{ msdyn_routingconfigurationid = $i.billingRc; msdyn_rulesetid = $i.billingRoute } } else { @{ msdyn_routingconfigurationid = $i.billingRc } }
        $i.billingStep = Add-CcFakeRecord $o msdyn_routingconfigurationstep @{ msdyn_name = 'Route to queue'; msdyn_uniquename = 'rcs_billing' } $stepLookups
        $i.omni = Add-CcFakeRecord $o msdyn_omnichannelconfiguration @{ msdyn_name = 'Omnichannel Configuration'; msdyn_number_of_declines_allowed = $(if ($side -eq 'dev') { 3 } else { 1 }) }
    }

    # Only in Dev.
    $d = $ids.dev
    $d.skillMortgages = Add-CcFakeRecord $dev characteristic @{ name = 'Mortgages'; characteristictype = 1 }
    $d.capChatB = Add-CcFakeRecord $dev msdyn_capacityprofile @{ msdyn_name = 'Chat capacity'; msdyn_uniquename = 'cap_chat_b'; msdyn_defaultmaxunits = 3; msdyn_blockassignment = $false }
    $d.mortgageSession = Add-CcFakeRecord $dev msdyn_sessiontemplate @{ msdyn_name = 'Mortgage session'; msdyn_uniquename = 'contoso_mortgage_session'; msdyn_title = 'Mortgage' }
    $d.mortgageNotification = Add-CcFakeRecord $dev msdyn_notificationtemplate @{ msdyn_name = 'Mortgage notification'; msdyn_uniquename = 'contoso_mortgage_notification'; msdyn_title = 'New mortgage chat'; msdyn_timeout = 60 }
    $d.gptNotification = Add-CcFakeRecord $dev msdyn_notificationtemplate @{ msdyn_name = 'ChatGPT notification'; msdyn_uniquename = 'msdyn_chatgpt_notification'; msdyn_title = 'GPT' } -Managed $true
    $d.mortgageQueue = Add-CcFakeRecord $dev queue @{ name = 'Mortgage queue'; msdyn_queuetype = 192350000; msdyn_isomnichannelqueue = $true; msdyn_priority = 2 } @{ msdyn_operatinghourid = $d.hours }
    $d.personalQueue = Add-CcFakeRecord $dev queue @{ name = '<Peter>'; msdyn_queuetype = 192350000; msdyn_isomnichannelqueue = $false; msdyn_priority = 1 }
    $d.mortgageContract = Add-CcFakeRecord $dev msdyn_decisioncontract @{ msdyn_name = 'Mortgage contract'; msdyn_uniquename = 'contoso_mortgage_contract'; msdyn_contractdefinition = '{"v":1}' }
    $d.mortgageRoute = Add-CcFakeRecord $dev msdyn_decisionruleset @{
        msdyn_name = 'Mortgage route'; msdyn_uniquename = 'contoso_mortgage_route'
        msdyn_rulesetdefinition = "<rules><rule queue=`"$($d.mortgageQueue)`" skill=`"$($d.skillMortgages)`"/></rules>"
    } @{ msdyn_inputcontractid = $d.mortgageContract }
    $d.mortgageChat = Add-CcFakeRecord $dev msdyn_liveworkstream ($chat + @{
            msdyn_name = 'Mortgage chat'; msdyn_capacityrequired = 1
            msdyn_sessiontemplate_default = 'contoso_mortgage_session'; msdyn_notificationtemplate_incoming_auth = 'contoso_mortgage_notification'
        }) @{ msdyn_defaultqueue = $d.mortgageQueue; msdyn_routingcontractid = $d.mortgageContract }
    $d.gptChat = Add-CcFakeRecord $dev msdyn_liveworkstream ($chat + @{
            msdyn_name = 'GPT chat'; msdyn_capacityrequired = 1; msdyn_notificationtemplate_incoming_auth = 'msdyn_chatgpt_notification'
        })
    $d.tierVariable = Add-CcFakeRecord $dev msdyn_ocliveworkstreamcontextvariable @{ msdyn_name = 'CustomerTier'; msdyn_datatype = 192350000; msdyn_islist = $false } @{ msdyn_liveworkstreamid = $d.mortgageChat }
    $d.mortgageCapacity = Add-CcFakeRecord $dev msdyn_liveworkstreamcapacityprofile @{ msdyn_name = 'Mortgage chat - Default' } @{ msdyn_workstream_id = $d.mortgageChat; msdyn_capacityprofile_id = $d.capDefault }
    $d.mortgageRc = Add-CcFakeRecord $dev msdyn_routingconfiguration @{ msdyn_name = 'Contact center routing configuration'; msdyn_uniquename = 'rc_mortgage'; msdyn_isactiveconfiguration = $true } @{ msdyn_liveworkstreamid = $d.mortgageChat }
    $d.mortgageStep = Add-CcFakeRecord $dev msdyn_routingconfigurationstep @{ msdyn_name = 'Route to queue'; msdyn_uniquename = 'rcs_mortgage' } @{ msdyn_routingconfigurationid = $d.mortgageRc; msdyn_rulesetid = $d.mortgageRoute }
    $d.whatsApp = Add-CcFakeRecord $dev msdyn_ocwhatsappchannelnumber @{ msdyn_name = 'Mortgage WhatsApp' } @{ msdyn_liveworkstreamid = $d.mortgageChat; msdyn_ocwidgetlanguage = $d.english; msdyn_ocwhatsappaccountid = [guid]::NewGuid().ToString() }
    $d.greeting = Add-CcFakeRecord $dev msdyn_cannedmessage @{ msdyn_title = 'Greeting'; msdyn_locale_field = 1033; msdyn_message = 'Hello, how can I help?' }
    $d.vip1 = Add-CcFakeRecord $dev msdyn_octag @{ msdyn_name = 'VIP' }
    $d.vip2 = Add-CcFakeRecord $dev msdyn_octag @{ msdyn_name = 'VIP' }
    $d.escalated = Add-CcFakeRecord $dev msdyn_octag @{ msdyn_name = 'Escalated' }
    $d.weekend1 = Add-CcFakeRecord $dev msdyn_operatinghour @{ msdyn_name = 'Weekend'; msdyn_description = 'Saturday' }
    $d.weekend2 = Add-CcFakeRecord $dev msdyn_operatinghour @{ msdyn_name = 'Weekend'; msdyn_description = 'Sunday' }

    # Many-to-many links, only in Dev.
    Add-CcFakeAssociation $dev msdyn_msdyn_cannedmessage_liveworkstream $d.greeting $d.mortgageChat
    Add-CcFakeAssociation $dev msdyn_msdyn_cannedmessage_liveworkstream $d.greeting $d.billingChat
    Add-CcFakeAssociation $dev msdyn_msdyn_cannedmessage_msdyn_octag $d.greeting $d.escalated

    # Only in Test.
    $ids.test.oldTag = Add-CcFakeRecord $test msdyn_octag @{ msdyn_name = 'Old tag' }

    return [pscustomobject]@{
        Dev     = $dev
        Test    = $test
        Ids     = $ids
        Envs    = @(
            New-CcFakeEnvironment -Id 'dev' -Name 'Dev' -Org $dev
            New-CcFakeEnvironment -Id 'test' -Name 'Test' -Org $test
        )
    }
}
