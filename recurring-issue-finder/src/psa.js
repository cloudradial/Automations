// Per-PSA parts of the Recurring Issue Finder agent and its goal workflow.
// build.js fills these into prompt.md and the YAML templates; test.js checks every tool
// named here against tools.json (a snapshot of the catalog extensions' tool names).

module.exports = {
  connectwise: {
    label: 'ConnectWise PSA',
    name: 'ConnectWise PSA',
    extension: 'connectwise-manage',
    kbWhere: 'ConnectWise has no KB tool, so put the draft at the end of the problem ticket description, under the heading "KB draft".',
    writeTools: ['cw_create_ticket'],
    steps: `## How to do it in ConnectWise PSA

Use only these tools: cw_query_boards, cw_query_tickets, cw_query_companies, cw_get_ticket, and cw_create_ticket (the only write).

- **Problem board:** call cw_query_boards with conditions \`name = "<board from the rules>"\` (default: a board whose name contains "Problem"). Record its id in your notes.
- **Tickets in the look-back:** one cw_query_tickets call with
  - conditions: \`dateEntered >= [<start date>T00:00:00Z] AND board/id != <problem board id> AND parentTicketId = null\` (add \`AND company/id != <id>\` for each skipped client)
  - fields: \`id,summary,company/id,company/name,board/name,type/name,subType/name,item/name,dateEntered\`
  - orderBy: \`dateEntered desc\`
  The start date is today minus the look-back days. If the call says it exceeded its record limit, run it again for the last 14 days and record that in your note.
- **Open problem tickets:** one cw_query_tickets call with conditions \`board/id = <problem board id> AND closedFlag = false\` and fields \`id,summary,company/id\`.
- **Confirm a theme (optional):** cw_get_ticket with one member ticket's id.
- **Propose:** cw_create_ticket with summary, boardId (the problem board), companyId (the theme's client), and initialDescription (the description below, including the KB draft). Add priorityId, typeId or subTypeId only when the Problem Ticket Standards name them and you resolved their ids; otherwise leave them out and the board defaults apply.`,
  },
  autotask: {
    label: 'Autotask',
    name: 'Autotask',
    extension: 'autotask-psa',
    kbWhere: 'Autotask has no KB tool here, so put the draft at the end of the problem ticket description, under the heading "KB draft".',
    writeTools: ['at_create_ticket'],
    steps: `## How to do it in Autotask

Use only these tools: at_get_ticket_field_values, at_query_tickets, at_get_company, at_get_ticket, and at_create_ticket (the only write).

- **Picklists first:** one at_get_ticket_field_values call. From it read the ids for ticketType "Problem", the problem queue (queueID, from the rules; default a queue whose name contains "Problem"), status "New", the priority from the rules (default "Medium"), the "Complete" status, and the labels of issueType and subIssueType. Record the problem queue, ticketType, status and priority ids in your notes so later check-ins can skip this call.
- **Tickets in the look-back:** one at_query_tickets call. The search is a JSON string, for example
  \`{"filter":[{"op":"gte","field":"createDate","value":"<start date>T00:00:00Z"},{"op":"noteq","field":"ticketType","value":<Problem id>},{"op":"noteq","field":"queueID","value":<problem queue id>}],"IncludeFields":["id","ticketNumber","title","companyID","issueType","subIssueType","queueID","createDate"]}\`
  (add \`{"op":"notIn","field":"companyID","value":[<ids>]}\` for skipped clients). Close every brace. The start date is today minus the look-back days. If the result passes 300 tickets, rerun it for the last 14 days and record that in your note.
- **Open problem tickets:** one at_query_tickets call filtering ticketType eq the Problem id and status noteq the Complete id, with IncludeFields id, title and companyID.
- **Client names:** at_get_company for the client of each top theme (at most 3 calls, in parallel).
- **Confirm a theme (optional):** at_get_ticket with one member ticket's internal id.
- **Propose:** at_create_ticket with title (the summary), companyID, ticketType (the Problem id), queueID (the problem queue), status (New), priority, dueDateTime (14 days from today, ISO 8601) and description. Ticket numbers in the description are the ticketNumber values (for example T20261101.0004), not internal ids.`,
  },
  halo: {
    label: 'HaloPSA',
    name: 'HaloPSA',
    extension: 'halo-psa',
    kbWhere: 'propose it as its own KB article too, with halo_create_kb_article (name = the title, description = symptoms and cause, resolution = the steps, inactive = true so it stays hidden until someone reviews it), and repeat its title at the end of the problem ticket description.',
    writeTools: ['halo_create_ticket', 'halo_create_kb_article'],
    steps: `## How to do it in HaloPSA

Use only these tools: halo_query_ticket_types, halo_query_tickets, halo_get_ticket, halo_create_ticket and halo_create_kb_article (the only writes).

- **Problem ticket type:** call halo_query_ticket_types with search set to the type from the rules (default "Problem"). Record its id in your notes.
- **Tickets in the look-back:** one halo_query_tickets call with startDate (today minus the look-back days), endDate (today), dateSearch "dateoccurred", pageinate true, page_size 300, order "dateoccurred" and orderdesc true. From each ticket use only id, summary, client_id, client_name, tickettype_id, category_1 and dateoccurred. Ignore tickets of the problem type. If more than 300 match, rerun it for the last 14 days and record that in your note.
- **Open problem tickets:** one halo_query_tickets call with ticketTypeId (the problem type) and open_only true.
- **Confirm a theme (optional):** halo_get_ticket with one member ticket's id.
- **Propose:** halo_create_ticket with summary, details (the description below), clientId (the theme's client) and tickettypeId (the problem type). Then halo_create_kb_article for the same theme. A problem ticket and its KB article count as one of your proposals.`,
  },
};
