using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CcAlm.Core.Tests
{
    /// <summary>
    /// The synthetic Dev and Test of tests/support/SyntheticScenario.ps1, on Microsoft's real Contact
    /// Center schema (tests/fixtures/schema.json): the same records, so both engines are held to the
    /// same expectations. See the table at the top of that file for what each record covers.
    /// </summary>
    public sealed class Scenario
    {
        public FakeDataverse Dev { get; }
        public FakeDataverse Test { get; }
        public Dictionary<string, Guid> DevIds { get; } = new Dictionary<string, Guid>();
        public Dictionary<string, Guid> TestIds { get; } = new Dictionary<string, Guid>();

        public static string RepoRoot
        {
            get
            {
                var dir = AppContext.BaseDirectory;
                while (dir != null && !File.Exists(Path.Combine(dir, "config", "manifest.json"))) dir = Path.GetDirectoryName(dir);
                return dir ?? throw new InvalidOperationException("Cannot find the repo root (config/manifest.json).");
            }
        }

        static Dictionary<string, JObject> _schema;
        public static Dictionary<string, JObject> Schema => _schema ?? (_schema = FakeDataverse.LoadMetadata(Path.Combine(RepoRoot, "tests", "fixtures", "schema.json")));

        static Dictionary<string, object> V(params object[] kv)
        {
            var d = new Dictionary<string, object>();
            for (int i = 0; i < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
            return d;
        }
        static Dictionary<string, Guid> L(params object[] kv)
        {
            var d = new Dictionary<string, Guid>();
            for (int i = 0; i < kv.Length; i += 2) d[(string)kv[i]] = (Guid)kv[i + 1];
            return d;
        }

        public Scenario(bool provisionRoutingContract = false, bool recordRouting = false, bool solutionCopies = false)
        {
            Dev = new FakeDataverse("Dev", "https://contoso-dev.crm4.dynamics.com", Schema);
            Test = new FakeDataverse("Test", "https://contoso-test.crm4.dynamics.com", Schema) { ProvisionRoutingContract = provisionRoutingContract };

            foreach (var side in new[] { "dev", "test" })
            {
                var o = side == "dev" ? Dev : Test;
                var i = side == "dev" ? DevIds : TestIds;
                var dev = side == "dev";
                i["english"] = o.Add("msdyn_oclanguage", V("msdyn_languagename", "English", "msdyn_localeid", 1033L));
                i["hours"] = o.Add("msdyn_operatinghour", V("msdyn_name", "Office hours"));
                i["skillBilling"] = o.Add("characteristic", V("name", "Billing", "characteristictype", 1L));
                i["capDefault"] = o.Add("msdyn_capacityprofile", V("msdyn_name", "Default", "msdyn_uniquename", "default_profile", "msdyn_defaultmaxunits", 100L, "msdyn_blockassignment", false));
                i["capChatA"] = o.Add("msdyn_capacityprofile", V("msdyn_name", "Chat capacity", "msdyn_uniquename", "cap_chat_a", "msdyn_defaultmaxunits", 2L, "msdyn_blockassignment", false));
                i["session"] = o.Add("msdyn_sessiontemplate", V("msdyn_name", "Chat session", "msdyn_uniquename", "msdyn_chat_session", "msdyn_title", "Chat"));
                i["billingQueue"] = o.Add("queue", V("name", "Billing queue", "msdyn_queuetype", 192350000L, "msdyn_isomnichannelqueue", true, "msdyn_priority", 1L), L("msdyn_operatinghourid", i["hours"]));
                i["billingContract"] = o.Add("msdyn_decisioncontract", V("msdyn_name", "Billing contract", "msdyn_uniquename", "contoso_billing_contract", "msdyn_contractdefinition", dev ? "{\"v\":2}" : "{\"v\":1}"));
                i["billingRoute"] = o.Add("msdyn_decisionruleset", V("msdyn_name", "Billing route", "msdyn_uniquename", "contoso_billing_route",
                    "msdyn_rulesetdefinition", $"<rules><rule queue=\"{i["billingQueue"]}\" skill=\"{i["skillBilling"].ToString().ToUpperInvariant()}\"/></rules>"));
                i["billingChat"] = o.Add("msdyn_liveworkstream", Chat(V("msdyn_name", "Billing chat", "msdyn_capacityrequired", dev ? 2L : 1L, "msdyn_allowedpresences", dev ? "192360000,192360001" : "192360001,192360000", "msdyn_sessiontemplate_default", "msdyn_chat_session")), L("msdyn_defaultqueue", i["billingQueue"]));
                i["billingRc"] = o.Add("msdyn_routingconfiguration", V("msdyn_name", "Contact center routing configuration", "msdyn_uniquename", "rc_billing", "msdyn_isactiveconfiguration", true), L("msdyn_liveworkstreamid", i["billingChat"]));
                i["billingStep"] = o.Add("msdyn_routingconfigurationstep", V("msdyn_name", "Route to queue", "msdyn_uniquename", "rcs_billing"),
                    dev ? L("msdyn_routingconfigurationid", i["billingRc"], "msdyn_rulesetid", i["billingRoute"]) : L("msdyn_routingconfigurationid", i["billingRc"]));
                i["omni"] = o.Add("msdyn_omnichannelconfiguration", V("msdyn_name", "Omnichannel Configuration", "msdyn_number_of_declines_allowed", dev ? 3L : 1L));
            }

            var d = DevIds;
            d["skillMortgages"] = Dev.Add("characteristic", V("name", "Mortgages", "characteristictype", 1L));
            d["capChatB"] = Dev.Add("msdyn_capacityprofile", V("msdyn_name", "Chat capacity", "msdyn_uniquename", "cap_chat_b", "msdyn_defaultmaxunits", 3L, "msdyn_blockassignment", false));
            d["mortgageSession"] = Dev.Add("msdyn_sessiontemplate", V("msdyn_name", "Mortgage session", "msdyn_uniquename", "contoso_mortgage_session", "msdyn_title", "Mortgage"));
            d["mortgageNotification"] = Dev.Add("msdyn_notificationtemplate", V("msdyn_name", "Mortgage notification", "msdyn_uniquename", "contoso_mortgage_notification", "msdyn_title", "New mortgage chat", "msdyn_timeout", 60L));
            d["gptNotification"] = Dev.Add("msdyn_notificationtemplate", V("msdyn_name", "ChatGPT notification", "msdyn_uniquename", "msdyn_chatgpt_notification", "msdyn_title", "GPT"), managed: true);
            d["mortgageQueue"] = Dev.Add("queue", V("name", "Mortgage queue", "msdyn_queuetype", 192350000L, "msdyn_isomnichannelqueue", true, "msdyn_priority", 2L), L("msdyn_operatinghourid", d["hours"]));
            d["personalQueue"] = Dev.Add("queue", V("name", "<Peter>", "msdyn_queuetype", 192350000L, "msdyn_isomnichannelqueue", false, "msdyn_priority", 1L));
            d["mortgageContract"] = Dev.Add("msdyn_decisioncontract", V("msdyn_name", "Mortgage contract", "msdyn_uniquename", "contoso_mortgage_contract", "msdyn_contractdefinition", "{\"v\":1}"));
            d["mortgageRoute"] = Dev.Add("msdyn_decisionruleset", V("msdyn_name", "Mortgage route", "msdyn_uniquename", "contoso_mortgage_route",
                "msdyn_rulesetdefinition", $"<rules><rule queue=\"{d["mortgageQueue"]}\" skill=\"{d["skillMortgages"]}\"/></rules>"), L("msdyn_inputcontractid", d["mortgageContract"]));
            d["mortgageChat"] = Dev.Add("msdyn_liveworkstream", Chat(V("msdyn_name", "Mortgage chat", "msdyn_capacityrequired", 1L, "msdyn_allowedpresences", "192360000,192360001",
                "msdyn_sessiontemplate_default", "contoso_mortgage_session", "msdyn_notificationtemplate_incoming_auth", "contoso_mortgage_notification")),
                L("msdyn_defaultqueue", d["mortgageQueue"], "msdyn_routingcontractid", d["mortgageContract"]));
            d["gptChat"] = Dev.Add("msdyn_liveworkstream", Chat(V("msdyn_name", "GPT chat", "msdyn_capacityrequired", 1L, "msdyn_notificationtemplate_incoming_auth", "msdyn_chatgpt_notification")));
            d["tierVariable"] = Dev.Add("msdyn_ocliveworkstreamcontextvariable", V("msdyn_name", "CustomerTier", "msdyn_datatype", 192350000L, "msdyn_islist", false), L("msdyn_liveworkstreamid", d["mortgageChat"]));
            d["mortgageCapacity"] = Dev.Add("msdyn_liveworkstreamcapacityprofile", V("msdyn_name", "Mortgage chat - Default"), L("msdyn_workstream_id", d["mortgageChat"], "msdyn_capacityprofile_id", d["capDefault"]));
            d["mortgageRc"] = Dev.Add("msdyn_routingconfiguration", V("msdyn_name", "Contact center routing configuration", "msdyn_uniquename", "rc_mortgage", "msdyn_isactiveconfiguration", true), L("msdyn_liveworkstreamid", d["mortgageChat"]));
            d["mortgageStep"] = Dev.Add("msdyn_routingconfigurationstep", V("msdyn_name", "Route to queue", "msdyn_uniquename", "rcs_mortgage"), L("msdyn_routingconfigurationid", d["mortgageRc"], "msdyn_rulesetid", d["mortgageRoute"]));
            d["whatsApp"] = Dev.Add("msdyn_ocwhatsappchannelnumber", V("msdyn_name", "Mortgage WhatsApp"), L("msdyn_liveworkstreamid", d["mortgageChat"], "msdyn_ocwidgetlanguage", d["english"]));
            // The WhatsApp account lookup points at a table this tool does not move.
            Dev.Find("msdyn_ocwhatsappchannelnumber", d["whatsApp"]).Values["msdyn_ocwhatsappaccountid"] = new Model.LookupValue("msdyn_ocwhatsappaccount", Guid.NewGuid());
            d["greeting"] = Dev.Add("msdyn_cannedmessage", V("msdyn_title", "Greeting", "msdyn_locale_field", 1033L, "msdyn_message", "Hello, how can I help?"));
            d["vip1"] = Dev.Add("msdyn_octag", V("msdyn_name", "VIP"));
            d["vip2"] = Dev.Add("msdyn_octag", V("msdyn_name", "VIP"));
            d["escalated"] = Dev.Add("msdyn_octag", V("msdyn_name", "Escalated"));
            d["weekend1"] = Dev.Add("msdyn_operatinghour", V("msdyn_name", "Weekend", "msdyn_description", "Saturday"));
            d["weekend2"] = Dev.Add("msdyn_operatinghour", V("msdyn_name", "Weekend", "msdyn_description", "Sunday"));

            // Many-to-many links, only in Dev.
            Dev.Link("msdyn_msdyn_cannedmessage_liveworkstream", d["greeting"], d["mortgageChat"]);
            Dev.Link("msdyn_msdyn_cannedmessage_liveworkstream", d["greeting"], d["billingChat"]);
            Dev.Link("msdyn_msdyn_cannedmessage_msdyn_octag", d["greeting"], d["escalated"]);

            TestIds["oldTag"] = Test.Add("msdyn_octag", V("msdyn_name", "Old tag"));

            if (solutionCopies)
            {
                // What a solution import leaves behind: Test has Dev's assignment method and its step as
                // managed copies with the same unique names, but no queue and an older name. A second
                // managed method with that older name and no queue has nothing to do with it.
                d["billingMethod"] = Dev.Add("msdyn_assignmentconfiguration", V("msdyn_name", "Billing assignment", "msdyn_uniquename", "msdyn_uniquename_billing"), L("msdyn_queueid", d["billingQueue"]));
                d["billingMethodStep"] = Dev.Add("msdyn_assignmentconfigurationstep", V("msdyn_name", "Inbound only", "msdyn_uniquename", "msdyn_uniquename_billing_step"), L("msdyn_assignmentconfigurationid", d["billingMethod"]));
                var e = TestIds;
                e["billingMethod"] = Test.Add("msdyn_assignmentconfiguration", V("msdyn_name", "Inbound only", "msdyn_uniquename", "msdyn_uniquename_billing"), managed: true);
                e["billingMethodStep"] = Test.Add("msdyn_assignmentconfigurationstep", V("msdyn_name", "Inbound only", "msdyn_uniquename", "msdyn_uniquename_billing_step"), L("msdyn_assignmentconfigurationid", e["billingMethod"]), managed: true);
                e["otherMethod"] = Test.Add("msdyn_assignmentconfiguration", V("msdyn_name", "Inbound only", "msdyn_uniquename", "msdyn_uniquename_other"), managed: true);
            }

            if (recordRouting)
            {
                // A case routing hub in both, with its intake ruleset from a managed solution. Dev sends
                // billing cases to Billing chat, then mortgage cases to Mortgage chat (new); Test has its
                // own rule first and the same billing rule, and keeps its own rule when Mortgage cases is merged in.
                foreach (var dev in new[] { true, false })
                {
                    var o = dev ? Dev : Test;
                    var i = dev ? DevIds : TestIds;
                    var rules = dev
                        ? new[] { IntakeRuleXml("Billing cases", 1, i["billingChat"]), IntakeRuleXml("Mortgage cases", 2, i["mortgageChat"]) }
                        : new[] { IntakeRuleXml("Test cases", 3, i["billingChat"]), IntakeRuleXml("Billing cases", 1, i["billingChat"]) };
                    i["intakeRuleset"] = o.Add("msdyn_decisionruleset", V("msdyn_name", "Case decision ruleset", "msdyn_uniquename", "new_incidentmasterentityroutingconfiguration",
                        "msdyn_rulesetdefinition", "<decision hit-policy=\"first\" version=\"1\">\n  <rules>\n    " + string.Join("\n    ", rules) + "\n  </rules>\n</decision>"), managed: true);
                    i["caseHub"] = o.Add("msdyn_masterentityroutingconfiguration", V("msdyn_name", "Case routing hub", "msdyn_entitylogicalname", "incident", "msdyn_uniquename", "new_incident"), L("msdyn_rulesetid", i["intakeRuleset"]));
                }
            }
        }

        /// <summary>One record routing intake rule as the admin center writes it: a condition, then the workstream.</summary>
        public static string IntakeRuleXml(string name, int caseType, Guid workstream) =>
            $"<rule id=\"{Guid.NewGuid()}\" name=\"{name}\"><condition operator=\"==\"><lhs type=\"attribute\">incident.casetypecode</lhs><rhs type=\"staticvalue\">{caseType}</rhs></condition><action><setattribute><lhs type=\"attribute\">action.unifiedrouting</lhs><rhs type=\"staticvalue\">{{{workstream}}}</rhs></setattribute></action></rule>";

        static Dictionary<string, object> Chat(Dictionary<string, object> v)
        {
            v["msdyn_mode"] = 192350000L;
            v["msdyn_streamsource"] = 192360000L;
            v["msdyn_direction"] = 192350000L;
            v["msdyn_workdistributionmode"] = 192350000L;
            return v;
        }
    }
}
