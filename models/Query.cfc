<cfcomponent extends="Model">
	<cfscript>
	
	function init() {
		belongsTo(name="Schema_Def", foreignKey="schema_def_id");		
	}
	
	</cfscript>
	
	<cffunction name="executeSQL" returnType="struct">
		<cfset var returnVal = {}>
		<cfset var resultInfo = {}>
		<cfset var ret = QueryNew("")>
		<cfset var executionPlan = QueryNew("")>
		<cfset var statement = "">
		<cfset var sqlBatchList = "">

		<cfif not IsDefined("this.schema_def") OR not IsDefined("this.schema_def.db_type")>
			<cfset this.schema_def = model("Schema_Def").findByKey(key=this.schema_def_id, include="DB_Type")>
		</cfif>
		
		<cfif this.schema_def.db_type.context IS "host">
				
			<cfset returnVal["sets"] = []>
			
			<cftransaction>
		
				<cfif Len(this.schema_def.db_type.batch_separator)>
					<cfset sqlBatchList = REReplace(this.sql, "#chr(10)##this.schema_def.db_type.batch_separator#(#chr(13)#?)#chr(10)#", '#chr(7)#', 'all')>
				<cfelse>
					<cfset sqlBatchList = this.sql>
				</cfif>
	
				<cfset sqlBatchList = REReplace(sqlBatchList, ";\s*(\r?\n|$)", "#chr(7)#", "all")>
	
				<cftry>
	
	              	<cfloop list="#sqlBatchList#" index="statement" delimiters="#chr(7)#">
						<cfset local.ret = QueryNew("")>
						<cfset local.executionPlan = QueryNew("")>
	
						<cfif Len(trim(statement))><!--- don't run empty queries --->
	
							<!--- if there is an execution plan mechanism available for this db type --->
							<cfif 		(
										Len(this.schema_def.db_type.execution_plan_prefix) OR
										Len(this.schema_def.db_type.execution_plan_suffix)
									) 
								>					
										
								<cfset local.executionPlanSQL = this.schema_def.db_type.execution_plan_prefix & statement & this.schema_def.db_type.execution_plan_suffix> 
								<cfset local.executionPlanSQL = Replace(local.executionPlanSQL, "##schema_short_code##", this.schema_def.short_code, "ALL")>
								<cfset local.executionPlanSQL = Replace(local.executionPlanSQL, "##query_id##", this.id, "ALL")>
	
								<cfif Len(this.schema_def.db_type.batch_separator)>
									<cfset local.executionPlanBatchList = REReplace(local.executionPlanSQL, "#chr(10)##this.schema_def.db_type.batch_separator#(#chr(13)#?)#chr(10)#", '#chr(7)#', 'all')>
								<cfelse>
									<cfset local.executionPlanBatchList = local.executionPlanSQL>
								</cfif>

								<cfloop list="#local.executionPlanBatchList#" index="executionPlanStatement" delimiters="#chr(7)#">
								<cftry>	
									<cfquery datasource="#this.schema_def.db_type_id#_#this.schema_def.short_code#" name="executionPlan">#PreserveSingleQuotes(executionPlanStatement)#</cfquery>								
									<cfcatch type="database">
									<!--- execution plan failed! Oh well, carry on.... --->
									<cfset local.executionPlan = QueryNew("")>
									</cfcatch>
								</cftry>								
								</cfloop>
	
								<!--- Some db types offer XML for the execution plan, which can allow for customized output --->
								<cfif 	
									IsDefined("local.executionPlan") AND 
									IsQuery(local.executionPlan) AND 
									local.executionPlan.recordCount AND
									IsXML(local.executionPlan[ListFirst(local.executionPlan.columnList)][1])>

									<!--- if we have xslt available for this db type, use it to transform the execution plan response --->
									<cfif Len(this.schema_def.db_type.execution_plan_xslt)>
										<cfset local.executionPlan[ListFirst(local.executionPlan.columnList)][1] = 
											XMLTransform(
												local.executionPlan[ListFirst(local.executionPlan.columnList)][1],
												this.schema_def.db_type.execution_plan_xslt
											)>								
									<cfelse>
										<!--- no XSLT, so just format it nicely --->
			
                                    	<cfset local.executionPlan[ListFirst(local.executionPlan.columnList)][1] =
                                            	"<pre>#XMLFormat(local.executionPlan[ListFirst(local.executionPlan.columnList)][1])#</pre>">
																				
									</cfif><!--- end if xslt is/is not available for type --->

								</cfif><!--- end if xml-based execution plan --->
	
	
							</cfif> <!--- end if execution plan --->
							
							<!--- run the actual query --->
							<cfquery datasource="#this.schema_def.db_type_id#_#this.schema_def.short_code#" name="ret" result="resultInfo">#PreserveSingleQuotes(statement)#</cfquery>
	
							<cfif IsDefined("local.ret")>
								
								<!--- change null values to the string "(null)" for better display --->
								<cfloop query="local.ret">
									<cfloop list="#local.ret.columnList#" index="local.colName">
										<cfset local.NullTest = local.ret.getString(local.colName)>
										
										<cfif not StructKeyExists(local, "NullTest")>
											<cfset QuerySetCell(local.ret, local.colName, "(null)", local.ret.currentRow)>
										<cfelse>
											<cfset structDelete(local, "NullTest")>
										</cfif>
									</cfloop>
									
								</cfloop>
								
								<cfset ArrayAppend(returnVal["sets"], {
									succeeded = true,
									results = Duplicate(ret),
									ExecutionTime = (IsDefined("resultInfo.ExecutionTime") ? resultInfo.ExecutionTime : 0),
									ExecutionPlan = ((IsDefined("local.executionPlan") AND IsQuery(local.executionPlan) AND local.executionPlan.recordCount) ? Duplicate(local.executionPlan) : [])
									})>
							<cfelse>
								<cfset ArrayAppend(returnVal["sets"], {
									succeeded = true,
									results = {"DATA" = []},
									ExecutionTime = (IsDefined("resultInfo.ExecutionTime") ? resultInfo.ExecutionTime : 0),
									ExecutionPlan = ((IsDefined("local.executionPlan") AND IsQuery(local.executionPlan) AND local.executionPlan.recordCount) ? Duplicate(local.executionPlan) : [])
									})>
							</cfif>
							
							
	
						</cfif>
						
						<cfset StructDelete(local, "executionPlan")>
						<cfset StructDelete(local, "ret")>
	              	</cfloop>
					
					<cfcatch type="database">
						<cfset ArrayAppend(returnVal["sets"], {
							succeeded = false,
							errorMessage = (IsDefined("cfcatch.queryError") ? (cfcatch.message & ": " & cfcatch.queryError) : cfcatch.message)
							})>
<!---
						<cfdump var="#statement#">
						<cfrethrow>
--->
					</cfcatch>
					<cffinally>		
						<cftransaction action="rollback" />
					</cffinally>
					
				</cftry>
	
	
			</cftransaction>

		</cfif>
		
		<cfreturn returnVal>
	</cffunction>
</cfcomponent>
