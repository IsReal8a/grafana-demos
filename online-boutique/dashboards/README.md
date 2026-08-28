# Executive Dashboard for Online Boutique

This directory contains a business-focused executive dashboard designed to present Online Boutique metrics in a way that's appealing and understandable to upper management.

## 📊 Dashboard Overview

The **Executive Dashboard** provides a high-level view of:

### Key Performance Indicators (KPIs)
- 🟢 **System Availability** - Overall uptime percentage
- ⚡ **Response Time (P95)** - 95th percentile latency
- ❌ **Error Rate** - Percentage of failed requests
- 📊 **Request Rate** - Requests per second

### Business Metrics
- 📈 **Traffic by Service** - Request volume trends
- ⏱️ **Response Time by Service** - Performance breakdown
- 🏪 **Service Health Overview** - Comprehensive service status table
- 📊 **HTTP Status Codes Distribution** - Success vs error breakdown

### Infrastructure Health
- 💻 **CPU Usage by Pod** - Resource utilization
- 💾 **Memory Usage by Pod** - Memory consumption
- 🚨 **Recent Errors & Exceptions** - Real-time error monitoring

## 🎯 Target Audience

This dashboard is designed for:
- **C-Level Executives** (CEO, CTO, COO)
- **Product Managers**
- **Business Stakeholders**
- **Non-technical Leadership**

## 📥 How to Import the Dashboard

### Method 1: Import via Grafana UI (Recommended)

1. **Log in to your Grafana Cloud instance**
   - Navigate to your Grafana Cloud URL
   - Use your credentials to log in

2. **Navigate to Dashboards**
   - Click on the **☰** menu (top left)
   - Select **Dashboards**
   - Click **New** → **Import**

3. **Upload the Dashboard JSON**
   - Click **Upload JSON file**
   - Select `executive-dashboard.json` from this directory
   - Or copy/paste the JSON content directly

4. **Configure Data Sources**
   - **Prometheus Data Source**: Select your Prometheus/Mimir data source
   - **Loki Data Source**: Select your Loki data source
   - Click **Import**

5. **Save and View**
   - The dashboard will open automatically
   - Click the **⭐ (star)** icon to favorite it
   - Set auto-refresh to 30 seconds for live updates

### Method 2: Import via Grafana API

```bash
# Set your Grafana Cloud details
GRAFANA_URL="https://your-instance.grafana.net"
GRAFANA_API_KEY="your-service-account-token"

# Import the dashboard
curl -X POST \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @executive-dashboard.json \
  "${GRAFANA_URL}/api/dashboards/db"
```

### Method 3: Import via Terraform

```hcl
resource "grafana_dashboard" "online_boutique_executive" {
  config_json = file("${path.module}/executive-dashboard.json")
  
  overwrite = true
  message   = "Updated by Terraform"
}
```

## 🎨 Dashboard Features

### Visual Design
- **Clean Layout**: Organized in logical sections
- **Color-Coded Metrics**: Color Blind compatible
- **Emoji Icons**: Quick visual identification of metrics
- **Responsive Design**: Works on desktop and large displays

### Interactive Elements
- **Time Range Selector**: View data from last hour to last 30 days
- **Auto-Refresh**: Updates every 30 seconds by default
- **Drill-Down**: Click on metrics to explore details
- **Tooltips**: Hover for additional information

### Threshold-Based Alerts
- **Availability**: Red < 95%, Yellow 95-99%, Green > 99%
- **Response Time**: Green < 500ms, Yellow 500-1000ms, Red > 1000ms
- **Error Rate**: Green < 1%, Yellow 1-5%, Red > 5%

## 📋 Dashboard Sections Explained

### Section 1: KPI Gauges (Top Row)
Four large gauges showing the most critical metrics at a glance:
- Quick health check in under 5 seconds
- Color-coded for instant status recognition
- Perfect for executive briefings

### Section 2: Traffic & Performance Trends
Two time-series charts showing:
- **Traffic by Service**: Which services are handling the most load
- **Response Time by Service**: Which services are performing well/poorly

### Section 3: Service Health Table
Comprehensive table showing all services with:
- Status (UP/DOWN)
- Request rate
- Average response time
- Success rate
- Color-coded for quick scanning

### Section 4: Distribution & Resources
Three visualizations:
- **HTTP Status Codes**: Pie chart of response codes
- **CPU Usage**: Resource consumption by pod
- **Memory Usage**: Memory consumption by pod

### Section 5: Error Monitoring
Real-time log stream showing:
- Errors and exceptions
- Failed requests
- System issues
- Filtered for critical keywords

## 🎯 Use Cases

### 1. Executive Briefings
- Open dashboard on large screen
- Show KPI gauges for instant status
- Highlight trends and improvements

### 2. Incident Response
- Quick identification of problem services
- Error rate and response time spikes
- Real-time error logs for troubleshooting

### 3. Performance Reviews
- Historical trends over time
- Service-level performance comparison
- Resource utilization patterns

### 4. Capacity Planning
- CPU and memory usage trends
- Traffic growth patterns
- Service scaling needs

### 5. Business Reporting
- Availability SLA compliance
- Performance metrics for stakeholders
- System health status reports

## 🔧 Customization

### Modify Thresholds
Edit the JSON file to adjust warning/critical thresholds:

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 500},  // Adjust this
    {"color": "red", "value": 1000}     // Adjust this
  ]
}
```

### Add Custom Panels
1. Open the dashboard in Grafana
2. Click **Add** → **Visualization**
3. Configure your panel
4. Click **Apply**
5. Save the dashboard

### Change Time Ranges
Default time range is **Last 1 hour**. To change:
1. Click the time picker (top right)
2. Select a different range
3. Click **Save dashboard** → **Save current time range**

### Modify Auto-Refresh
Default is **30 seconds**. To change:
1. Click the refresh dropdown (top right)
2. Select a different interval
3. Or disable auto-refresh

## 📊 Metrics Reference

### Prometheus Queries Used

**System Availability:**
```promql
avg(up{namespace="boutique"}) * 100
```

**Response Time (P95):**
```promql
histogram_quantile(0.95, sum(rate(http_server_duration_milliseconds_bucket{namespace="boutique"}[$__rate_interval])) by (le))
```

**Error Rate:**
```promql
sum(rate(http_server_duration_milliseconds_count{namespace="boutique",http_status_code=~"5.."}[$__rate_interval])) / sum(rate(http_server_duration_milliseconds_count{namespace="boutique"}[$__rate_interval]))
```

**Request Rate:**
```promql
sum(rate(http_server_duration_milliseconds_count{namespace="boutique"}[$__rate_interval]))
```

### Loki Queries Used

**Error Logs:**
```logql
{namespace="boutique"} |~ "(?i)(error|exception|fail|fatal|panic)"
```

## 🎬 Demo Tips

### For Presentations
1. **Start with KPIs**: Show the four gauges first
2. **Tell a Story**: Walk through traffic → performance → health
3. **Show Real-Time**: Demonstrate auto-refresh capability
4. **Drill Down**: Click on a service to show detailed metrics
5. **Show Errors**: Scroll to error logs to show monitoring capability

### For Stakeholder Meetings
1. **Focus on Availability**: "We maintain 99.9% uptime"
2. **Highlight Performance**: "95% of requests complete in under 200ms"
3. **Show Trends**: "Traffic has grown 20% this month"
4. **Demonstrate Monitoring**: "We detect and alert on issues immediately"

### For Technical Reviews
1. **Service-Level Details**: Use the health table
2. **Resource Utilization**: Show CPU/Memory charts
3. **Error Analysis**: Review error logs
4. **Performance Optimization**: Identify slow services

## 🚀 Next Steps

After importing the dashboard:

1. **Set Up Alerts**
   - Create alert rules for critical metrics
   - Configure notification channels (email, Slack, PagerDuty)
   - Test alert delivery

2. **Create Snapshots**
   - Take snapshots for reports
   - Share with stakeholders
   - Archive for historical reference

3. **Schedule Reports**
   - Set up automated PDF reports
   - Email to stakeholders weekly/monthly
   - Include in executive briefings

4. **Customize for Your Needs**
   - Add business-specific metrics
   - Adjust thresholds based on SLAs
   - Include cost metrics if available

## 📚 Additional Resources

- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [PromQL Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)

## 🆘 Troubleshooting

### No Data Showing
1. Verify data sources are configured correctly
2. Check that Online Boutique is running: `kubectl get pods -n boutique`
3. Verify Grafana Alloy is collecting metrics: `kubectl get pods -n grafana-stack`
4. Check time range (default is last 1 hour)

### Metrics Missing
1. Ensure Grafana Alloy is forwarding to Grafana Cloud
2. Verify namespace is "boutique" in queries
3. Check that services have OpenTelemetry instrumentation enabled

### Dashboard Looks Different
1. Grafana version differences may affect rendering
2. Update to latest Grafana version
3. Check panel plugin versions

### Performance Issues
1. Reduce time range (use last 1 hour instead of 24 hours)
2. Increase refresh interval (use 1 minute instead of 30 seconds)
3. Limit number of series in charts
