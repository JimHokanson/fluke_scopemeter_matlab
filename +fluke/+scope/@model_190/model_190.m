classdef model_190
    %UNTITLED2 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Hidden)
        s 	% serial port object data
        
        %BaudRate is selectable and could be something else
        %Other values are from Appendix F in the User Manual (PHD2000)
        serial_options = {...
            'BaudRate',NaN,...
            'DataBits',8,...
            'Parity','none',...
            'StopBits',2,...
            'Terminator',[]... %This is because the response is non-standard
            }
    end
    
    properties
    end
    
    methods
        
    end
    
    methods (Hidden)
        function response = runQuery(obj,cmd)
            %
            
            CR = char(13);
            LF = char(10);
            
            s2 = obj.s;
            full_cmd = sprintf('%d %s \r',obj.address,cmd);
            fprintf(s2,full_cmd);

            %Model 44
            %<lf><text><cr> - 1 or more lines
            %<lf> 1 or 2 digit address, prompt char => e.g. 1:
            %  :  pump stopped
            %  >  pump infusing
            %  <  pump refilling
            %  /  pause interval, pump stopped
            %  *  pumping interrupted (pump stopped)
            %  ^  dispense trigger wait (pump stopped)
            
            %OPTIONS
            %-----------------------
            PAUSE_DURATION = 0.005;
            MAX_INITIAL_WAIT_TIME = 2;
            MAX_READ_TIME = 5;
            
            %Error Codes
            %----------------------
            %<lf>,space,space,<message><cr>
            %   where message is 1 of:
            %   ? - syntax error
            %   NA - command not applicable at this time
            %   OOR - control data is out of the operating range of the
            %   pump
            
            ERROR_1 = [LF '  ?' CR];
            ERROR_2 = [LF '  NA' CR];
            ERROR_3 = [LF '  OOR' CR];
            
            %TODO: Why aren't these hidden
            %             obj.addlistener
            %             obj.delete
            %             obj.findobj
            %             obj.findprop
            
            %Note, don't include CR because some responses are only the
            %end of message indicator
            END_OF_MSG_START = sprintf('%s%d',LF,obj.address);
            n_chars_back = length(END_OF_MSG_START);
            
            %Wait until we get something
            %----------------------------------
            i = 0;
            while s2.BytesAvailable == 0
                pause(PAUSE_DURATION);
                i = i + 1;
                if PAUSE_DURATION*i > MAX_INITIAL_WAIT_TIME
                    %This can occur if:
                    %1) The baud rate is incorrect
                    %
                    %2) Multiple commands are sent to the device
                    %   without appropriate blocking
                    %
                    %3) The pump is currently in a menu :/
                    %
                    %4) ****** Pump gets turned off
                    error('Something wrong happened')
                end
            end
            
            %Read the response
            %-----------------------------------
            t1 = tic;
            response = [];
            done = false;
            while ~done
                
                if obj.s.BytesAvailable
                    response = [response fscanf(obj.s,'%c',obj.s.BytesAvailable)]; %#ok<AGROW>
                    
                    %Expecting Model 44 - model 22 starts with CR ...
                    if response(1) == LF
                        switch response(end)
                            case {':' '>' '<' '/' '*' '^'}
                                if length(response) >= n_chars_back + 1 && ...
                                        strcmp(response(end-n_chars_back:end-1),END_OF_MSG_START)
                                    
                                    %  :  pump stopped
                                    %  >  pump infusing
                                    %  <  pump refilling
                                    %  /  pause interval, pump stopped
                                    %  *  pumping interrupted (pump stopped)
                                    %  ^  dispense trigger wait (pump stopped)
                                    last_char = response(end);
                                    response = response(1:end-n_chars_back-1);
                                    
                                    switch response
                                        case ERROR_1
                                            error('Syntax error for cmd: "%s"',full_cmd)
                                        case ERROR_2
                                            error('Command not applicable at this time')
                                        case ERROR_3
                                            error('Control data out of range for this pump')
                                    end

                                    %YUCK :/
                                    %--------------------------------------
                                    switch last_char
                                        case ':'
                                            ps = '3: stopped'; %ps => Pump Status
                                        case '>'
                                            ps = '1: infusing';
                                        case '<'
                                            ps = '2: refilling';
                                        case '/'
                                            ps = '4: paused';
                                        case '*'
                                            ps = '5: pumping interrupted';
                                        case '^'
                                            ps = '6: dispense trigger wait';
                                        otherwise
                                            ps = '7: unrecognized';
                                            
                                    end
                                    obj.pump_status_from_last_query = ps;
                                    
                                    done = true;
                                end
                            case CR
                                %I don't think this ever runs ...
                                %It is unclear whether or not
                                switch response
                                    case ERROR_1
                                        error('Syntax error')
                                    case ERROR_2
                                        error('Command not applicable at this time')
                                    case ERROR_3
                                        error('Control data out of range for this pump')
                                    otherwise
                                        %Keep reading ...
                                end
                            otherwise
                                %Here we need to read more ...
                                %Keep going
                        end
                    else
                        error('Unexpected first character')
                    end
                else
                    pause(PAUSE_DURATION);
                end
                
                if (~done && toc(t1) > MAX_READ_TIME)
                    error('Response timed out')
                end
            end
        end
    end
    
end

function h__initSerial(obj,input,in)
%
%
%   Inputs
%   -------
%   input : 


if ischar(input)
    port_name = input;
elseif isnumeric(input)
    port_name = sprintf('COM%d',input);
else
    error('Unexpected COMinput')
end

% check to see if requests serial port exists
serial_info = instrhwinfo('serial');

if ~any(strcmp(serial_info.AvailableSerialPorts,port_name))
    if any(strcmp(serial_info.SerialPorts,port_name))
        %delete(instrfindall) will delete everything in Matlab
        fprintf(2,'You may use "delete(instrfindall)" to clear all serial ports\n')
        error('Requested serial port: %s is in use',port_name);
    else
        fprintf(2,'-----------------------------\n');
        fprintf(2,'Requested serial port: %s was not found\n',port_name)
        fprintf(2,'Available ports:\n')
        sp = serial_info.SerialPorts;
        for i = 1:length(sp)
            fprintf(2,'%s\n',sp{i})
        end
        fprintf(2,'-------------------------\n')
        error('See above for error info');
    end
end
obj.s = serial(port_name);



set(obj.s,obj.serial_options{:});
fopen(obj.s);

end
