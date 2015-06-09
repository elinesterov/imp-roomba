# imp-roomba
Roomba remote control using electric imp platform

you can send command to agent in the following way:

curl https://agent.electricimp.com/agent_url/api/device_mac?command=status

where https://agent.electricimp.com/agent_url - agent url 
      device mac - device mac

command could be :
                   - clean 
                   - sleep 
                   - doc 
                   - spot
                   - status

